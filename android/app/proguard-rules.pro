# Release builds shrink and rename classes (R8). ONNX Runtime's native code
# finds its Java classes by name (TensorInfo, OnnxTensor, ...), so renaming
# them crashes the first math reading: "JNI DETECTED ERROR: java_class ==
# null in call to GetMethodID from ai.onnxruntime.OrtSession.run".
# flutter_onnxruntime's README asks for this rule.
-keep class ai.onnxruntime.** { *; }
