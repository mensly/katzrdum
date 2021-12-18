package cat.balrog.katzrdum.sample

import android.content.DialogInterface
import androidx.annotation.Keep
import androidx.appcompat.app.AlertDialog
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.DefaultLifecycleObserver
import androidx.lifecycle.LifecycleOwner
import androidx.lifecycle.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.launch
import java.lang.ref.WeakReference
import java.util.UUID

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
    }

    constructor(vararg fields: ConfigField<out Any>): this(fields.toList())

    private inner class LifecycleObserver(activity: AppCompatActivity) : DefaultLifecycleObserver, DialogInterface.OnClickListener {
        private val activity = WeakReference(activity)
        private var code = "MOCK"

        override fun onResume(owner: LifecycleOwner) {
            super.onResume(owner)
            startUdpListener()
            if (BuildConfig.DEBUG) {
                val scope = activity.get()?.lifecycle?.coroutineScope ?: return
                scope.launch {
                    delay(9001)
                    showPrompt()
                }
            }
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
            // TODO

        }

        private fun stopUdpListener() {
            // TODO
        }

        private fun connectToTcp() {
            // TODO
        }

        private fun showPrompt() {
            val activity = this.activity.get() ?: return
            AlertDialog.Builder(activity)
                .setMessage(configPrompt.replace(CODE_PLACEHOLDER, code))
                .setPositiveButton(android.R.string.ok, this)
                .setNegativeButton(android.R.string.cancel, this)
                .show()
        }

        override fun onClick(dialog: DialogInterface, selection: Int) {
            if (selection == DialogInterface.BUTTON_POSITIVE) {
                connectToTcp()
                if (BuildConfig.DEBUG) {
                    val scope = activity.get()?.lifecycle?.coroutineScope ?: return
                    scope.launch {
                        val key = fields.firstOrNull()?.key ?: "message"
                        postConfiguration(key, UUID.randomUUID().toString())
                    }
                }
            }
        }
    }

    var configPrompt = "Would you like to configure using Katzrdum found on your network?\nCODE: $CODE_PLACEHOLDER"

    private val configurationsFlow = MutableSharedFlow<Pair<String, Any>>()

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

class IntegerField(key: String, @Keep val default: Long = 0): ConfigField<Long>(key) {
    override val type = "Integer"
    override var value = default
}

class DataField(key: String, @Keep val default: ByteArray = byteArrayOf()): ConfigField<ByteArray>(key) {
    override val type = "Data"
    override var value = default
}
