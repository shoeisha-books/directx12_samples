#pragma once
#include<d3d12.h>
#include<wrl.h>
#include<vector>
#include<memory>

using Microsoft::WRL::ComPtr;
class PMDActor;
class Dx12Wrapper;

///PMD描画のための共通部分を
///ここに持っている
///個別の部分はPMDActorに持たせる
class PMDRenderer
{
private:
	bool CreateRootSignature();
	bool CreatePipeline();
	ComPtr<ID3D12PipelineState> _pls;
	ComPtr<ID3D12PipelineState> _plsShadow;

	ComPtr<ID3D12RootSignature> _rootSignature;
	std::vector<std::shared_ptr<PMDActor>> _actors;
	std::shared_ptr<Dx12Wrapper> _dx;
public:
	PMDRenderer(std::shared_ptr<Dx12Wrapper> dx);
	~PMDRenderer();

	void Init();
	
	void AddActor(std::shared_ptr<PMDActor> actor);
	void AddActor(const char* filepath);
	ID3D12RootSignature* RootSignature();
	ID3D12PipelineState* Pipeline();

	void Update();

	void BeforeDrawFromLight();
	void DrawFromLight();

	void BeforeDraw();

	void Draw();
	void AnimationStart();
};

