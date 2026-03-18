# Official vLLM Neuron DLC (vLLM 0.13.0 + Neuron SDK 2.28.0)
FROM public.ecr.aws/neuron/pytorch-inference-vllm-neuronx:0.13.0-neuronx-py312-sdk2.28.0-ubuntu24.04

# Only thing we need on top for Ray Serve LLM
RUN pip install --no-cache-dir \
    "ray[serve,llm]==2.54.0" \
    "ray[default]" \
    && rm -rf /root/.cache/pip

ENV HF_HOME=/root/.cache/huggingface