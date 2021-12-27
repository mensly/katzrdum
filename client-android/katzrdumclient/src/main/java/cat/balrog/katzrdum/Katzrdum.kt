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
import java.security.KeyPair
import java.security.KeyPairGenerator
import java.security.PrivateKey
import java.security.PublicKey
import java.security.spec.X509EncodedKeySpec
import java.util.Base64
import javax.crypto.Cipher
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
        private const val KEY_PUBLIC_KEY = "key"
        private const val KEY_FIELDS = "fields"
        private const val PORT_UDP = 21055
        private const val PORT_TCP = 24990
        private const val BUFFER_SIZE = 1024 // TODO: Set to actual size of public key datum, probably a lot smaller!
        private const val UDP_TIMEOUT = 500
        private const val DELIMITER = ':'
        private const val BLOCK_SIZE = 512

        private fun getPublicKey(base64PublicKey: String): PublicKey {
            val joinedKey = base64PublicKey.split("\n").joinToString(separator = "")
            val keySpec =
                X509EncodedKeySpec(Base64.getDecoder().decode(joinedKey.toByteArray()))
            val keyFactory: KeyFactory = KeyFactory.getInstance("RSA")
            return keyFactory.generatePublic(keySpec)
        }

        private fun encrypt(message: String, publicKey: String): ByteArray {
            val cipher: Cipher = Cipher.getInstance("RSA/ECB/PKCS1Padding")
            cipher.init(Cipher.ENCRYPT_MODE, getPublicKey(publicKey))
            message.toByteArray(Charsets.UTF_8).subarrays(BLOCK_SIZE).forEach(cipher::update)
            return cipher.doFinal()
        }

        private fun decrypt(message: String, privateKey: PrivateKey): String {
            val cipher: Cipher = Cipher.getInstance("RSA/ECB/PKCS1Padding")
            cipher.init(Cipher.DECRYPT_MODE, privateKey)
            message.toByteArray(Charsets.UTF_8).subarrays(BLOCK_SIZE).forEach(cipher::update)
            return String(cipher.doFinal(), Charsets.UTF_8)
        }
//        final _intMax = BigInt.from(9223372036854775807);
//        String calculateCode(String encodedPublicKey) {
//            var sum = BigInt.zero;
//            for (final byte in encodedPublicKey.codeUnits) {
//                sum = (sum + BigInt.from(byte)) % _intMax;
//            }
//            return sum.toRadixString(10).substring(1);
//        }
        private val longMax = Long.MAX_VALUE.toBigInteger()
        private fun calculateCode(encodedPublicKey: String): String {
            var sum = BigInteger.ZERO
            for (byte in encodedPublicKey.codePoints()) {
                sum = (sum + byte.toBigInteger()) % longMax
            }
            return sum.toString().substring(1)
        }
    }

    constructor(vararg fields: ConfigField<out Any>): this(fields.toList())

    private inner class LifecycleObserver(activity: AppCompatActivity) : DefaultLifecycleObserver, DialogInterface.OnClickListener {
        private val activity = WeakReference(activity)
        private var remoteHost: InetAddress? = null
        private var remotePublicKey: String? = null
        private var udpSocket by ClosingDelegate<DatagramSocket>()
        private var tcpSocket by ClosingDelegate<Socket>()

        override fun onResume(owner: LifecycleOwner) {
            super.onResume(owner)
            handledKeys.clear()
            startUdpListener()
            // netcat -l 24990
//            remoteHost = InetAddress.getByName("192.168.20.10")
//            remotePublicKey = "MOCK"
//            connectToTcp()
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
                    if (message != null && message !in handledKeys && remotePublicKey != message) {
                        Log.d(TAG, "Received UDP: $message from ${packet.address}")
                        remoteHost = packet.address
                        remotePublicKey = message
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
                val keyGen: KeyPairGenerator = KeyPairGenerator.getInstance("RSA")
                keyGen.initialize(4096)
                // FIXME: RSA can only encrypt data smaller than (or equal to) the key length. The answer is to encrypt the data with a symmetric algorithm such as AES which is designed to encrypt small and large data.
                // Need to generate a SHARED key, send that to the mine encrypted using the mine's public key
                // Encrypt all TCP comms after that (sending config and receiving values) using AES
                val keyPair: KeyPair = keyGen.generateKeyPair()
                val localPublicKey = Base64.getEncoder().encodeToString(keyPair.public.encoded)
//                val config = mapOf(
//                    KEY_PUBLIC_KEY to localPublicKey,
//                    KEY_FIELDS to fields
//                ).toString() // TODO: Encode with JSON via kotlinx.serialization
                val config = "{\"key\":\"$localPublicKey\",\"fields\":[" + fields.joinToString { "{\"name\":\"${it.name}\"" } + "}]}"
                Log.d(TAG, "config: $config")
                Log.d(TAG, "remotePublicKey: $remotePublicKey")
//                val originalMessage = "Hello Brave New World"
//                Log.d(TAG, originalMessage);
//                Log.d(TAG, localPublicKey)
//                val cipherMessage = String(encrypt(originalMessage, localPublicKey))
//                Log.d(TAG, cipherMessage)
//                val decodedMessage = decrypt(cipherMessage, keyPair.private)
//                Log.d(TAG, decodedMessage)

                try {
                    Socket(remoteHost, PORT_TCP).use { socket ->
                        tcpSocket = socket
                        Log.d(TAG, "TCP Socket connected: $socket")
                        socket.getOutputStream().apply {
                            write(encrypt(config, remotePublicKey))
                            flush()
                        }
                        Log.d(TAG, "Config sent")
                        socket.getInputStream().bufferedReader().forEachLine { encryptedData ->
                            // TODO: Read in config values
                            Log.d(TAG, "Received TCP: $encryptedData")
                            val data = decrypt(encryptedData, keyPair.private)
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
            val code = this.remotePublicKey?.let(::calculateCode) ?: return
            AlertDialog.Builder(activity)
                .setMessage(configPrompt.replace(CODE_PLACEHOLDER, code))
                .setPositiveButton(android.R.string.ok, this)
                .setNegativeButton(android.R.string.cancel, this)
                .setCancelable(false)
                .show()
        }

        override fun onClick(dialog: DialogInterface, selection: Int) {
            remotePublicKey?.let(handledKeys::add)
            if (selection == DialogInterface.BUTTON_POSITIVE) {
                connectToTcp()
            }
        }
    }

    var configPrompt = "Would you like to configure using Katzrdum found on your network?\nCODE: $CODE_PLACEHOLDER"

    private val configurationsFlow = MutableSharedFlow<Pair<String, Any>>()
    private val handledKeys = mutableListOf<String>()

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