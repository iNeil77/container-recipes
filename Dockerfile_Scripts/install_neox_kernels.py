from megatron.fused_kernels import load
import os

os.environ['TORCH_CUDA_ARCH_LIST'] = '6.0;6.1;7.0;7.5;8.0;8.6;8.6;8.9;9.0;10.0+PTX'
load()
