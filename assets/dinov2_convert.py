import onnx
from onnx.external_data_helper import convert_model_to_external_data

# --------------------------------------------------------------
# CONFIG
# --------------------------------------------------------------
in_model  = "assets/dinov2.onnx"         # your original IR10 model
out_model = "dinov2.onnx"     # final IR9 model
data_file = "dinov2.onnx.data"
tensor_threshold = 1024  # everything >1KB will go into the .data file
# --------------------------------------------------------------

# 1) Load original model
model = onnx.load(in_model)

# 2) Downgrade IR version
model.ir_version = 9

# 3) Convert ALL tensors into ONE external .data file
convert_model_to_external_data(
    model,
    all_tensors_to_one_file=True,
    location=data_file,
    size_threshold=tensor_threshold,
    convert_attribute=False
)

# 4) Save model
onnx.save(model, out_model)

print("DONE — Generated:")
print(f"• {out_model}")
print(f"• {data_file}")
