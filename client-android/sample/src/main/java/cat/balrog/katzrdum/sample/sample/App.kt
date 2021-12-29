package cat.balrog.katzrdum.sample.sample

import android.app.Application
import android.graphics.Color
import cat.balrog.katzrdum.*
import com.squareup.moshi.Moshi
import org.koin.android.ext.koin.androidContext
import org.koin.android.ext.koin.androidLogger
import org.koin.core.context.startKoin
import org.koin.dsl.module
import java.math.BigDecimal

class App : Application() {
    override fun onCreate() {
        super.onCreate()

        val module = module {
            single { Moshi.Builder().build() }
            single {
                val jsonAdp = get<Moshi>().adapter(KatzrdumConfig::class.java)
                Katzrdum(
                    StringField(KEY_MESSAGE),
                    PasswordField(KEY_PASSWORD),
                    ColorField(KEY_BACKGROUND, default = Color.BLACK),
                    NumberField(KEY_FAV_NUMBER, default = BigDecimal(42))
                ) {
                    jsonAdp.toJson(it)
                }
            }
        }

        startKoin {
            androidLogger()
            androidContext(this@App)
            modules(module)
        }
    }
}