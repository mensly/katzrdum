package cat.balrog.katzrdum.sample.sample

import android.annotation.SuppressLint
import android.os.Bundle
import android.view.Gravity
import android.widget.TextView
import androidx.appcompat.app.AppCompatActivity
import androidx.lifecycle.asLiveData
import cat.balrog.katzrdum.sample.Katzrdum
import org.koin.core.component.KoinComponent
import org.koin.core.component.inject

const val KEY_MESSAGE = "message"

class MainActivity : AppCompatActivity(), KoinComponent {
    private val katzdumClient by inject<Katzrdum>()

    @SuppressLint("SetTextI18n")
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val textView = TextView(this)
        textView.textAlignment = TextView.TEXT_ALIGNMENT_CENTER
        textView.gravity = Gravity.CENTER
        textView.text = getString(R.string.text)
        setContentView(textView)
        val config = katzdumClient.listen(this).asLiveData()
        config.observe(this) {
            val (key, value) = it
            when (key) {
                // In a real application, you might persist this value or process it somehow
                KEY_MESSAGE -> textView.text = "${getString(R.string.text)}\n$value"
            }
        }
    }
}