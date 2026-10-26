# Release builds shrink and rename classes (R8). ONNX Runtime's native code
# finds its Java classes by name (TensorInfo, OnnxTensor, ...), so renaming
# them crashes the first math reading: "JNI DETECTED ERROR: java_class ==
# null in call to GetMethodID from ai.onnxruntime.OrtSession.run".
# flutter_onnxruntime's README asks for this rule.
-keep class ai.onnxruntime.** { *; }

# flutter_local_notifications keeps scheduled reminders as JSON (Gson) and
# reads them back after a restart. Its own rules ship with it since v19; this
# keeps its model classes whole too, so a renamed field can't drop a reminder.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
