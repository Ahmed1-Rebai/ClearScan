# The ML Kit text-recognition plugin references the optional Chinese, Devanagari,
# Japanese and Korean recognizers. Only the Latin model is bundled, so those
# classes are absent and must not fail R8 in release builds.
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**
