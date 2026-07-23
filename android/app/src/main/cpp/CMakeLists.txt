cmake_minimum_required(VERSION 3.18)
project(sync_audio_opus)

add_library(sync_audio_opus SHARED opus_codec_jni.cpp)
target_link_libraries(sync_audio_opus log dl)
