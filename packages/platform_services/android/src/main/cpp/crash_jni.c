#include <jni.h>
#include "../../../../native/crash_capture.h"
JNIEXPORT jint JNICALL Java_com_genotv_platform_1services_NativeCrash_install(JNIEnv *env, jobject self, jstring path) {
  (void)self;
  if (!path) return EINVAL;
  const char *value = (*env)->GetStringUTFChars(env, path, NULL);
  if (!value) return ENOMEM;
  int code = vp_crash_install(value);
  (*env)->ReleaseStringUTFChars(env, path, value);
  return code;
}
JNIEXPORT void JNICALL Java_com_genotv_platform_1services_NativeCrash_uninstall(JNIEnv *env, jobject self) {
  (void)env; (void)self; vp_crash_uninstall();
}
JNIEXPORT void JNICALL Java_com_genotv_platform_1services_NativeCrash_abort(JNIEnv *env, jobject self) {
  (void)env; (void)self; vp_crash_abort();
}
