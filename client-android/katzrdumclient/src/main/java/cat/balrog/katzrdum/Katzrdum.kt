package cat.balrog.katzrdum

import android.content.DialogInterface
import android.util.Log
import androidx.annotation.Keep
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.coroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.launch
import java.io.Closeable
import java.lang.ref.WeakReference
import java.math.BigInteger
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.Socket
import java.net.SocketException
import java.net.SocketTimeoutException
import java.security.KeyFactory
import java.security.PublicKey
import java.security.SecureRandom
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.IvParameterSpec
import kotlin.concurrent.thread
import kotlin.math.min
import kotlin.reflect.KProperty


/**
 * Connect to a Katzrdum configuration instance on the local network.
 * This library is contained to a single file so that it may be easily copied
 * into a Google Glass Enterprise Edition project. As per
 * https://developers.google.com/glass-enterprise/guides/inputs-sensors#detect-activity-level-gestures
 *
 * See https://mine.balrog.cat/#/config
 */
class Katzrdum(private val fields: List<ConfigField<out Any>>) {
    companion object {
        const val CODE_PLACEHOLDER = "\${__CODE__}"
        private const val TAG = "Katz"
        private const val KEY_FIELDS = "fields"
        private const val PORT_UDP = 21055
        private const val PORT_TCP = 24990
        private const val BUFFER_SIZE = 1024 // TODO: Set to actual size of public key datum, probably a lot smaller!
        private const val UDP_TIMEOUT = 500
        private const val DELIMITER = ':'
        private const val IV_SIZE = 16
        private const val ALGORITHM_ASYMMETRIC = "RSA/ECB/PKCS1Padding";
        private const val ALGORITHM_SYMMETRIC = "AES/CBC/PKCS5Padding";
        private val LONG_MAX = Long.MAX_VALUE.toBigInteger()

        private fun parsePublicKey(base64PublicKey: String): Pair<PublicKey, IvParameterSpec> {
            val joinedKey = base64PublicKey.split("\n").joinToString(separator = "")
            val keyData = Base64.getDecoder().decode(joinedKey.toByteArray())
            val keySpec = X509EncodedKeySpec(keyData)
            val keyFactory: KeyFactory = KeyFactory.getInstance("RSA")
            val publicKey = keyFactory.generatePublic(keySpec)
            val iv = IvParameterSpec(keyData.sliceArray(0 until IV_SIZE - 1))
            Log.d(TAG, "$base64PublicKey -> $publicKey")
            return publicKey to iv
        }

        private fun encrypt(data: ByteArray, publicKey: PublicKey): ByteArray {
            val cipher: Cipher = Cipher.getInstance(ALGORITHM_ASYMMETRIC)
            cipher.init(Cipher.ENCRYPT_MODE, publicKey)
            return cipher.doFinal(data)
        }

        private fun encrypt(message: String, secretKey: SecretKey): ByteArray {
            val cipher: Cipher = Cipher.getInstance(ALGORITHM_SYMMETRIC)
            cipher.init(Cipher.ENCRYPT_MODE, secretKey)
            return cipher.doFinal(message.toByteArray(Charsets.UTF_8))
        }

        private fun decrypt(message: String, secretKey: SecretKey): String {
            val cipher: Cipher = Cipher.getInstance(ALGORITHM_SYMMETRIC)
            cipher.init(Cipher.DECRYPT_MODE, secretKey)
            return String(cipher.doFinal(message.toByteArray(Charsets.UTF_8)), Charsets.UTF_8)
        }

        private fun calculateCode(encodedPublicKey: String): String {
            var sum = BigInteger.ZERO
            for (byte in encodedPublicKey.codePoints()) {
                sum = (sum + byte.toBigInteger()) % LONG_MAX
            }
            return sum.toString().substring(1)
        }
    }

    constructor(vararg fields: ConfigField<out Any>): this(fields.toList())

    private inner class LifecycleObserver(activity: AppCompatActivity) : DefaultLifecycleObserver, DialogInterface.OnClickListener {
        private val activity = WeakReference(activity)
        private var remoteHost: InetAddress? = null
        private var remoteMessage: String? = null
        private var remotePublicKey: PublicKey? = null
        private var code: String? = null
        private var iv: IvParameterSpec? = null
        private var udpSocket by ClosingDelegate<DatagramSocket>()
        private var tcpSocket by ClosingDelegate<Socket>()

        override fun onResume(owner: LifecycleOwner) {
            super.onResume(owner)
            handledKeys.clear()
            startUdpListener()
        }

        override fun onPause(owner: LifecycleOwner) {
            super.onPause(owner)
            udpSocket = null
            tcpSocket = null
        }

        override fun onDestroy(owner: LifecycleOwner) {
            super.onDestroy(owner)
            owner.lifecycle.removeObserver(this)
        }

        private fun runOnMain(block: suspend ()->Unit) {
            activity.get()?.lifecycle?.coroutineScope?.launch {
                block()
            }
        }

        private fun startUdpListener() {
            thread {
                val socket = DatagramSocket(PORT_UDP)
                val buffer = ByteArray(BUFFER_SIZE)
                val packet = DatagramPacket(buffer, BUFFER_SIZE)
                udpSocket = socket
                while (!socket.isClosed) {
//                    Log.d(TAG, System.currentTimeMillis().toString())
                    socket.soTimeout = UDP_TIMEOUT
                    val message = try {
                        socket.receive(packet)
                        String(buffer, 0, packet.length)
                    } catch (e: SocketTimeoutException) {
                        null // Timeout is normal
                    } catch (e: SocketException) {
                        Log.e(TAG, "Error with UDP socket")
                        return@thread // end thread
                    }
                    if (message != null && message !in handledKeys && remoteMessage != message) {
                        Log.d(TAG, "Received UDP: $message from ${packet.address}")
                        remoteHost = packet.address
                        remoteMessage = message
                        val parsed = parsePublicKey(message)
                        remotePublicKey = parsed.first
                        iv = parsed.second
                        code = calculateCode(message)
                        runOnMain(this::showPrompt)
                    }
                }
            }

            // TODO: handle errors, restart and stuff
        }

        private fun connectToTcp() {
            val remoteHost = this.remoteHost ?: return
            val remotePublicKey = this.remotePublicKey ?: return
            thread {
                val keyGen = KeyGenerator.getInstance("AES");
                keyGen.init(SecureRandom.getInstanceStrong())
                val secretKey = keyGen.generateKey()
//                val config = mapOf(
//                    KEY_FIELDS to fields
//                ).toString() // TODO: Encode with JSON via kotlinx.serialization
                val config = "{\"fields\":[" + fields.joinToString { "{\"name\":\"${it.name}\"" } + "}]}"
                Log.d(TAG, "config: $config")
                Log.d(TAG, "remotePublicKey: $remotePublicKey")

                try {
                    Socket(remoteHost, PORT_TCP).use { socket ->
                        tcpSocket = socket
                        Log.d(TAG, "TCP Socket connected: $socket")
                        socket.getOutputStream().apply {
                            Log.d(TAG, "secretKey: ${String(Base64.getEncoder().encode(secretKey.encoded))}")
//                            write(encrypt(secretKey.encoded, remotePublicKey))
                            val encryptedSecret = encrypt("hello".toByteArray(), remotePublicKey)
                            Log.d(TAG, "encryptedSecret: ${String(Base64.getEncoder().encode(encryptedSecret))}")
                            write(encryptedSecret)
                            flush()
//                            write(encrypt(config, secretKey))
//                            flush()
                        }
                        Log.d(TAG, "Config sent")
                        socket.getInputStream().bufferedReader().forEachLine { encryptedData ->
                            // TODO: Read in config values
                            Log.d(TAG, "Received TCP: $encryptedData")
                            val data = decrypt(encryptedData, secretKey)
                            Log.d(TAG, "Received data: $data")
                            val dataIndex = data.indexOf(DELIMITER) + 1
                            if (dataIndex <= 0) return@forEachLine
                            val fieldName = data.substring(0, dataIndex - 1)
                            val field = fields.firstOrNull { it.name == fieldName }
                                ?: return@forEachLine
                            val rawValue = if (dataIndex == data.length) "" else data.substring(dataIndex)
                            val value = field.parse(rawValue)
                            runOnMain {
                                postConfiguration(fieldName, value)
                            }
                        }
                    }
                } catch (e: SocketException) {
                    // TODO
                }
                Log.d(TAG, "Socket closed")
                // TODO: handle errors, restart and stuff
            }
        }

        private fun showPrompt() {
            val activity = this.activity.get() ?: return
            val code = this.code ?: return
            AlertDialog.Builder(activity)
                .setMessage(configPrompt.replace(CODE_PLACEHOLDER, code))
                .setPositiveButton(android.R.string.ok, this)
                .setNegativeButton(android.R.string.cancel, this)
                .setCancelable(false)
                .show()
        }

        override fun onClick(dialog: DialogInterface, selection: Int) {
            remoteMessage?.let(handledKeys::add)
            if (selection == DialogInterface.BUTTON_POSITIVE) {
                connectToTcp()
            }
        }
    }

    var configPrompt = "Would you like to configure using Katzrdum found on your network?\nCODE: $CODE_PLACEHOLDER"

    private val configurationsFlow = MutableSharedFlow<Pair<String, Any>>()
    private val handledKeys = mutableListOf<String>()

    init {
        if (fields.any { it.name.contains(DELIMITER) }) {
            throw IllegalArgumentException("Character '$DELIMITER' is used as a delimiter and cannot be used in a field name")
        }
    }

    fun listen(activity: AppCompatActivity): Flow<Pair<String, Any>> {
        activity.lifecycle.addObserver(LifecycleObserver(activity))
        return configurationsFlow
    }

    suspend fun postConfiguration(key: String, value: Any) {
        configurationsFlow.emit(key to value)
    }
}

fun ByteArray.subarrays(maxSize: Int): Iterable<ByteArray> {
    val subsequenceCount = this.size / maxSize
    val subarrays = mutableListOf<ByteArray>()
    for (i in 0 until subsequenceCount - 1) {
        val startIndex = i * maxSize
        val endIndex = min(size, (i + 1) * maxSize) - 1
        subarrays += slice(startIndex until endIndex).toByteArray()
    }
    return subarrays
}

class ClosingDelegate<T: Closeable> {
    private var value: T? = null
    operator fun getValue(obj: Any, property: KProperty<*>) = value

    operator fun setValue(obj: Any, property: KProperty<*>, value: T?) {
//        this.value?.let { Log.d("Katz", "Closing $it") }
        this.value?.close()
        this.value = value
    }
}

sealed class ConfigField<T>(val name: String) {
    abstract val type: String
    abstract val value: T
    var label = name
    abstract fun parse(data: String): T
}

class StringField(name: String, @Keep val default: String = ""): ConfigField<String>(name) {
    override val type = "String"
    override var value = default
    override fun parse(data: String) = if (data.isEmpty()) default else data
}

class PasswordField(name: String, @Keep val default: String = ""): ConfigField<String>(name) {
    override val type = "Password"
    override var value = default
    override fun parse(data: String) = if (data.isEmpty()) default else data
}

class IntegerField(name: String, @Keep val default: Long = 0): ConfigField<Long>(name) {
    override val type = "Integer"
    override var value = default
    override fun parse(data: String) = if (data.isEmpty()) default else data.toLong()
}

class DataField(name: String, @Keep val default: ByteArray = byteArrayOf()): ConfigField<ByteArray>(name) {
    override val type = "Data"
    override var value = default
    override fun parse(data: String) = TODO("base64 decode")
}