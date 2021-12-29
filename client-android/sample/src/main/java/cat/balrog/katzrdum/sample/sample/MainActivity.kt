package cat.balrog.katzrdum.sample.sample

import android.annotation.SuppressLint
import android.os.Bundle
import android.util.TypedValue
import android.view.Gravity
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.asLiveData
import cat.balrog.katzrdum.Katzrdum
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject
import java.math.BigDecimal

const val KEY_MESSAGE = "message"
const val KEY_PASSWORD = "password"
const val KEY_BACKGROUND = "background"
const val KEY_FAV_NUMBER = "number"

class MainActivity : AppCompatActivity(), KoinComponent {
    private val katzdumClient by inject<Katzrdum>()
    private var message: String? = null
    private var authenticated = false
    private var favNumber: BigDecimal? = null

    @SuppressLint("SetTextI18n")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val defaultText = getString(R.string.text)
        val textView = TextView(this).apply {
            textAlignment = TextView.TEXT_ALIGNMENT_CENTER
            gravity = Gravity.CENTER
            text = defaultText
            setTextSize(TypedValue.COMPLEX_UNIT_SP, 24f)
            keepScreenOn = true
        }
        setContentView(textView)
        val config = katzdumClient.listen(this).asLiveData()
        config.observe(this) { (key, value) ->
            // In a real application, you might persist values or process it somehow
            when (key) {
                KEY_MESSAGE -> message = value as String
                KEY_PASSWORD -> authenticated = true
                KEY_BACKGROUND -> textView.setBackgroundColor(value as Int)
            }
            val authText = if (authenticated) getString(R.string.authenticated) else null
            val numberText = favNumber?.let { getString(R.string.fav_number, it.toPlainString()) }
            textView.text = listOfNotNull(defaultText, authText, numberText, message).joinToString()
        }
    }
}