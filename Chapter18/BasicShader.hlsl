SamplerState smp : register(s0);
SamplerState clutSmp : register(s1);
SamplerComparisonState shadowSmp : register(s2);

//マテリアル用スロット
cbuffer materialBuffer : register(b0) {
	float4 diffuse;
	float power;
	float3 specular;
	float3 ambient;
};
//マテリアル用
Texture2D<float4> tex : register(t0);//通常テクスチャ
Texture2D<float4> sph : register(t1);//スフィアマップ(乗算)
Texture2D<float4> spa : register(t2);//スフィアマップ(加算)
Texture2D<float4> toon : register(t3);//トゥーンテクスチャ

//シャドウマップ用
Texture2D<float> lightDepthTex : register(t4);//デプス

//シーン管理用スロット
cbuffer sceneBuffer : register(b1) {
	matrix view;//ビュー
	matrix proj;//プロジェクション
	matrix invPro;//逆射影行列
	matrix lightCamera;//ライトビュープロジェ
	matrix shadow;//影行列
	float3 eye;//視点
};

//アクター座標変換用スロット
cbuffer transBuffer : register(b2) {
	matrix world;
}

//ボーン行列配列
cbuffer transBuffer : register(b3) {
	matrix bones[512];
}

//表示設定
cbuffer DrawSetting : register(b4) {
	uint outline;
	uint rimFlg;
	float rimStrength;
}


//返すのはSV_POSITIONだけではない
struct Output {
	float4 svpos : SV_POSITION;
	float4 pos : POSITION;
	float4 tpos : TPOS;
	float4 normal : NORMAL;
	float2 uv : TEXCOORD;
	float instNo : INSTNO;
};
struct PixelOutput {
	float4 color:SV_TARGET0;//標準
	float4 normal:SV_TARGET1;//法線
	float4 highLum:SV_TARGET2;//高輝度
};

struct PrimitiveOutput {
	float4 svpos:SV_POSITION;
	float4 tpos : TPOS;
	float4 normal:NORMAL;
};



PrimitiveOutput PrimitiveVS(float4 pos:POSITION, float4 normal : NORMAL) {
	PrimitiveOutput output;
	output.svpos = mul(proj, mul(view, pos));
	output.tpos = mul(lightCamera, pos);
	output.normal = normal;
	return output;
}
PixelOutput PrimitivePS(PrimitiveOutput input){
	float3 light = normalize(float3(1,-1,1));
	float bright = dot(input.normal, -light);

	float shadowWeight = 1.0f;
	float3 posFromLightVP = input.tpos.xyz / input.tpos.w;
	float2 shadowUV = (input.tpos.xy / input.tpos.w + float2(1, -1))*float2(0.5, -0.5);
	float depthFromLight = lightDepthTex.SampleCmpLevelZero(
		shadowSmp,
		shadowUV,
		posFromLightVP.z - 0.005f);
	shadowWeight = lerp(0.5f, 1.0f, depthFromLight);

	float b = bright*shadowWeight;

	PixelOutput po;
	po.color=float4(b, b, b, 1);
	po.normal = float4((input.normal.xyz+1)*0.5,1);
	return po;
}

//頂点シェーダ(頂点情報から必要なものを次の人へ渡す)
//パイプラインに投げるためにはSV_POSITIONが必要
Output VS(float4 pos:POSITION,float4 normal:NORMAL,float2 uv:TEXCOORD,min16uint2 boneno:BONENO,min16uint weight:WEIGHT,uint instNo:SV_InstanceID) {
	//1280,720を直で使って構わない。
	Output output;
	float fWeight = float(weight) / 100.0f;
	matrix conBone = bones[boneno.x]*fWeight + 
						bones[boneno.y]*(1.0f - fWeight);

	output.pos = mul(world, 
						mul(conBone,pos)
					);
	//if (instNo == 0) {
	//	output.pos = mul(shadow, output.pos);
	//}
	output.instNo = (float)instNo;

	output.svpos = mul(proj,mul(view, output.pos));
	//output.svpos = mul(lightCamera, output.pos);
	output.tpos = mul(lightCamera, output.pos);
	output.uv = uv;
	normal.w = 0;
	output.normal = mul(world,mul(conBone,normal));
	//output.uv = uv;
	return output;
}



//ピクセルシェーダ
PixelOutput PS(Output input) {
	float3 eyeray = normalize(input.pos-eye);
	float3 light = normalize(float3(1,-1,1));
	float3 rlight = reflect(light, input.normal);
		
	//スペキュラ輝度
	float p = saturate(dot(rlight, -eyeray));

	//MSDNのpowのドキュメントによると
	//p=0だったりp==0&&power==0のときNANの可能性が
	//あるため、念のため以下のようなコードにしている
	//https://docs.microsoft.com/ja-jp/windows/win32/direct3dhlsl/dx-graphics-hlsl-pow
	float specB = 0;
	if (p > 0 && power > 0) {
		specB=pow(p, power);
	}

	//ディフューズ明るさ		
	float diffB = dot(-light, input.normal);
	float4 toonCol = toon.Sample(clutSmp, float2(0, 1 - diffB));
	

	float4 texCol =  tex.Sample(smp, input.uv);
	
	//col.rgb= pow(col.rgb, 1.0 / 2.2);
	float2 spUV= (input.normal.xy
		*float2(1, -1) //まず上下だけひっくりかえす
		+ float2(1, 1)//(1,1)を足して-1〜1を0〜2にする
		) / 2;
	float4 sphCol = sph.Sample(smp, spUV);
	float4 spaCol = spa.Sample(smp, spUV);
	
	//float4 ret= spaCol + sphCol * texCol*toonCol*diffuse + float4(ambient*0.6, 1)
	float4 ret = float4((spaCol + sphCol * texCol * toonCol*diffuse).rgb,diffuse.a)
		+ float4(specular*specB, 1);
	

	float shadowWeight = 1.0f;
	float3 posFromLightVP=input.tpos.xyz / input.tpos.w;
	float2 shadowUV = (input.tpos.xy/input.tpos.w+float2(1,-1))*float2(0.5,-0.5);
	float depthFromLight = lightDepthTex.SampleCmpLevelZero(
		shadowSmp, 
		shadowUV, 
		posFromLightVP.z-0.005f);
	shadowWeight = lerp(0.5f, 1.0f, depthFromLight);

	//float rim= rimFlg?dot(input.normal, -eyeray):0;
	float rim = rimFlg?pow(1.0f-saturate(dot(input.normal, -eyeray)),rimStrength):0.0f ;
	PixelOutput po;
	float4 retcol = float4(ret.rgb*shadowWeight + float3(rim, rim, rim), ret.a);
	po.color = retcol;
	po.normal = float4(0.5*(input.normal.rgb+1),1);
	po.highLum = float4(0,0,0,1);
	if (dot(float3(0.299f, 0.587f, 0.114f), retcol.rgb) > 0.95f) {
		po.highLum.rgb = float3(1, 1, 1);// step(0.99, retcol.rgb);
	}
	
	return po;
}

//影用頂点座標変換
float4 
shadowVS(float4 pos:POSITION, float4 normal : NORMAL, float2 uv : TEXCOORD, min16uint2 boneno : BONENO, min16uint weight : WEIGHT) :SV_POSITION{
	float fWeight = float(weight) / 100.0f;
	matrix conBone = bones[boneno.x] * fWeight +
						bones[boneno.y] * (1.0f - fWeight);

	pos = mul(world, mul(conBone, pos));
	return  mul(lightCamera, pos);
}

float4
shadowPS(float4 pos:SV_POSITION):SV_TARGET {
	return float4(1,1,1,1);
}
