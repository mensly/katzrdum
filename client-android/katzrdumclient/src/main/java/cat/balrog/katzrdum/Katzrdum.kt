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
import java.lang.ref.WeakReference
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.Socket
import java.net.SocketTimeoutException
import kotlin.concurrent.thread

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
        private const val KEY_PUBLIC_KEY = "key"
        private const val KEY_FIELDS = "fields"
        private const val PORT_UDP = 21055
        private const val PORT_TCP = 24990
        private const val BUFFER_SIZE = 1024 // TODO: Set to actual size of public key datum, probably a lot smaller!
        private const val UDP_TIMEOUT = 500
    }

    constructor(vararg fields: ConfigField<out Any>): this(fields.toList())

    private inner class LifecycleObserver(activity: AppCompatActivity) : DefaultLifecycleObserver, DialogInterface.OnClickListener {
        private val activity = WeakReference(activity)
        private var udpSocket: DatagramSocket? = null
        private var remoteHost: InetAddress? = null
        private var remotePublicKey: String? = null

        override fun onResume(owner: LifecycleOwner) {
            super.onResume(owner)
            startUdpListener()
        }

        override fun onPause(owner: LifecycleOwner) {
            super.onPause(owner)
            stopUdpListener()
        }

        override fun onDestroy(owner: LifecycleOwner) {
            super.onDestroy(owner)
            owner.lifecycle.removeObserver(this)
        }

        private fun startUdpListener() {
            thread {
                val socket = DatagramSocket(PORT_UDP)
                val buffer = ByteArray(BUFFER_SIZE)
                val packet = DatagramPacket(buffer, BUFFER_SIZE)
                udpSocket = socket
                while (!socket.isClosed) {
                    Log.d("Katz", System.currentTimeMillis().toString())
                    socket.soTimeout = UDP_TIMEOUT
                    val message = try {
                        socket.receive(packet)
                        String(buffer, 0, packet.length)
                    } catch (timeout: SocketTimeoutException) {
                        null
                    }
                    Log.d("Katz", "Received UDP: $message from $remoteHost")
                    if (message != null && message !in handledKeys && remotePublicKey != message) {
                        remoteHost = packet.address
                        remotePublicKey = message
                        val scope = activity.get()?.lifecycle?.coroutineScope
                        scope?.launch {
                            showPrompt()
                        }
                    }
                }
            }

            // TODO: handle errors, restart and stuff
        }

        private fun stopUdpListener() {
            udpSocket?.disconnect()
        }

        private fun connectToTcp() {
            val remoteHost = this.remoteHost ?: return
            val remotePublicKey = this.remotePublicKey ?: return
            // TODO: generate key pair and send public key
            val localPrivateKey = "clientmock]"
            val localPublicKey = "clientmock"
            thread {
                val config = mapOf(
                    KEY_PUBLIC_KEY to localPublicKey,
                    KEY_FIELDS to fields
                ).toString() // TODO: Encode with JSON via kotlinx.serialization
                Socket(remoteHost, PORT_TCP).use { socket ->
                    Log.d("Katz", "TCP Socket connected: $socket")
                    socket.getOutputStream().bufferedWriter().write(config)
                    socket.getInputStream().bufferedReader().lines().forEach {
                        // TODO: Read in config values
                        Log.d("Katz", "Received TCP: $it")
                    }
                }
                // TODO: handle errors, restart and stuff
            }
        }

        private fun showPrompt() {
            val activity = this.activity.get() ?: return
            val code = remotePublicKey?.substring(0, 4) ?: return
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

sealed class ConfigField<T>(val key: String) {
    abstract val type: String
    abstract val value: T
}

class StringField(key: String, @Keep val default: String = ""): ConfigField<String>(key) {
    override val type = "String"
    override var value = default
}

class PasswordField(key: String, @Keep val default: String = ""): ConfigField<String>(key) {
    override val type = "Password"
    override var value = default
}

class IntegerField(key: String, @Keep val default: Long = 0): ConfigField<Long>(key) {
    override val type = "Integer"
    override var value = default
}

class DataField(key: String, @Keep val default: ByteArray = byteArrayOf()): ConfigField<ByteArray>(key) {
    override val type = "Data"
    override var value = default
}
