package com.example.sync_audio

import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import javax.crypto.Cipher
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec

internal object NativeSecureAudioPacket {
    private val magic = byteArrayOf(0x53, 0x45, 0x01)

    fun encrypt(clearPacket: ByteArray, sessionId: String, pairingToken: String, sequence: Long): ByteArray {
        val nonce = nonce(sessionId, sequence)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.ENCRYPT_MODE, key(sessionId, pairingToken), GCMParameterSpec(128, nonce))
        cipher.updateAAD(sessionId.toByteArray(StandardCharsets.UTF_8))
        return magic + nonce + cipher.doFinal(clearPacket)
    }

    fun decrypt(wirePacket: ByteArray, sessionId: String, pairingToken: String): ByteArray? {
        if (wirePacket.size < magic.size + 12 + 16 || !wirePacket.copyOfRange(0, 3).contentEquals(magic)) return null
        val nonce = wirePacket.copyOfRange(3, 15)
        val cipher = Cipher.getInstance("AES/GCM/NoPadding")
        cipher.init(Cipher.DECRYPT_MODE, key(sessionId, pairingToken), GCMParameterSpec(128, nonce))
        cipher.updateAAD(sessionId.toByteArray(StandardCharsets.UTF_8))
        return try { cipher.doFinal(wirePacket.copyOfRange(15, wirePacket.size)) } catch (_: Exception) { null }
    }

    private fun key(sessionId: String, token: String): SecretKeySpec {
        val material = "sync_audio/v1|$sessionId|$token".toByteArray(StandardCharsets.UTF_8)
        return SecretKeySpec(MessageDigest.getInstance("SHA-256").digest(material), "AES")
    }

    private fun nonce(sessionId: String, sequence: Long): ByteArray {
        val prefix = MessageDigest.getInstance("SHA-256")
            .digest(sessionId.toByteArray(StandardCharsets.UTF_8))
        val result = ByteArray(12)
        prefix.copyInto(result, endIndex = 3)
        result[3] = 1
        ByteBuffer.wrap(result, 4, 8).order(ByteOrder.BIG_ENDIAN).putLong(sequence)
        return result
    }
}
