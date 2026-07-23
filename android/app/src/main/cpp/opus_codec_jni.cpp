#include <jni.h>
#include <dlfcn.h>
#include <cstdint>

namespace {
using Encoder = void;
using Decoder = void;
using EncoderCreate = Encoder* (*)(int, int, int, int*);
using EncoderDestroy = void (*)(Encoder*);
using Encode = int (*)(Encoder*, const int16_t*, int, unsigned char*, int);
using DecoderCreate = Decoder* (*)(int, int, int*);
using DecoderDestroy = void (*)(Decoder*);
using Decode = int (*)(Decoder*, const unsigned char*, int, int16_t*, int, int);

void* opusHandle = nullptr;
EncoderCreate encoderCreate = nullptr;
EncoderDestroy encoderDestroy = nullptr;
Encode encode = nullptr;
DecoderCreate decoderCreate = nullptr;
DecoderDestroy decoderDestroy = nullptr;
Decode decode = nullptr;

bool loadOpus() {
  if (opusHandle != nullptr) return encoderCreate != nullptr && decode != nullptr;
  opusHandle = dlopen("libopus.so", RTLD_NOW | RTLD_LOCAL);
  if (opusHandle == nullptr) return false;
  encoderCreate = reinterpret_cast<EncoderCreate>(dlsym(opusHandle, "opus_encoder_create"));
  encoderDestroy = reinterpret_cast<EncoderDestroy>(dlsym(opusHandle, "opus_encoder_destroy"));
  encode = reinterpret_cast<Encode>(dlsym(opusHandle, "opus_encode"));
  decoderCreate = reinterpret_cast<DecoderCreate>(dlsym(opusHandle, "opus_decoder_create"));
  decoderDestroy = reinterpret_cast<DecoderDestroy>(dlsym(opusHandle, "opus_decoder_destroy"));
  decode = reinterpret_cast<Decode>(dlsym(opusHandle, "opus_decode"));
  return encoderCreate && encoderDestroy && encode && decoderCreate && decoderDestroy && decode;
}
}  // namespace

extern "C" JNIEXPORT jboolean JNICALL
Java_com_example_sync_1audio_OpusCodecNative_nativeAvailable(JNIEnv*, jclass) {
  return loadOpus() ? JNI_TRUE : JNI_FALSE;
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_example_sync_1audio_OpusCodecNative_nativeCreateEncoder(
    JNIEnv*, jclass, jint sampleRate, jint channels) {
  if (!loadOpus()) return 0;
  int error = -1;
  return reinterpret_cast<jlong>(encoderCreate(sampleRate, channels, 2049, &error));
}

extern "C" JNIEXPORT jint JNICALL
Java_com_example_sync_1audio_OpusCodecNative_nativeEncode(
    JNIEnv* env, jclass, jlong handle, jbyteArray pcm, jbyteArray output) {
  if (handle == 0 || pcm == nullptr || output == nullptr || !loadOpus()) return -1;
  const auto pcmLength = env->GetArrayLength(pcm);
  const auto outputLength = env->GetArrayLength(output);
  if (pcmLength <= 0 || pcmLength % 2 != 0 || outputLength <= 0) return -1;
  jbyte* pcmBytes = env->GetByteArrayElements(pcm, nullptr);
  auto* pcmSamples = reinterpret_cast<const int16_t*>(pcmBytes);
  auto* encoded = new unsigned char[static_cast<size_t>(outputLength)];
  const int result = encode(
      reinterpret_cast<Encoder*>(handle), pcmSamples, pcmLength / 2, encoded, outputLength);
  if (result > 0) env->SetByteArrayRegion(output, 0, result, reinterpret_cast<const jbyte*>(encoded));
  delete[] encoded;
  env->ReleaseByteArrayElements(pcm, pcmBytes, JNI_ABORT);
  return result;
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_sync_1audio_OpusCodecNative_nativeDestroyEncoder(JNIEnv*, jclass, jlong handle) {
  if (handle != 0 && encoderDestroy != nullptr) encoderDestroy(reinterpret_cast<Encoder*>(handle));
}

extern "C" JNIEXPORT jlong JNICALL
Java_com_example_sync_1audio_OpusCodecNative_nativeCreateDecoder(
    JNIEnv*, jclass, jint sampleRate, jint channels) {
  if (!loadOpus()) return 0;
  int error = -1;
  return reinterpret_cast<jlong>(decoderCreate(sampleRate, channels, &error));
}

extern "C" JNIEXPORT jint JNICALL
Java_com_example_sync_1audio_OpusCodecNative_nativeDecode(
    JNIEnv* env, jclass, jlong handle, jbyteArray encoded, jbyteArray pcm) {
  if (handle == 0 || encoded == nullptr || pcm == nullptr || !loadOpus()) return -1;
  const auto encodedLength = env->GetArrayLength(encoded);
  const auto pcmLength = env->GetArrayLength(pcm);
  if (encodedLength <= 0 || pcmLength <= 0 || pcmLength % 2 != 0) return -1;
  jbyte* encodedBytes = env->GetByteArrayElements(encoded, nullptr);
  auto* decoded = new int16_t[static_cast<size_t>(pcmLength / 2)];
  const int result = decode(
      reinterpret_cast<Decoder*>(handle),
      reinterpret_cast<const unsigned char*>(encodedBytes),
      encodedLength,
      decoded,
      pcmLength / 2,
      0);
  if (result > 0) {
    env->SetByteArrayRegion(
        pcm, 0, result * 2, reinterpret_cast<const jbyte*>(decoded));
  }
  delete[] decoded;
  env->ReleaseByteArrayElements(encoded, encodedBytes, JNI_ABORT);
  return result > 0 ? result * 2 : result;
}

extern "C" JNIEXPORT void JNICALL
Java_com_example_sync_1audio_OpusCodecNative_nativeDestroyDecoder(JNIEnv*, jclass, jlong handle) {
  if (handle != 0 && decoderDestroy != nullptr) decoderDestroy(reinterpret_cast<Decoder*>(handle));
}
