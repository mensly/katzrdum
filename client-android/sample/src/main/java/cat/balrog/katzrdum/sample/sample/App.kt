package cat.balrog.katzrdum.sample.sample

import android.app.Application
import android.graphics.Color
import cat.balrog.katzrdum.*
import org.koin.android.ext.koin.androidContext
import org.koin.android.ext.koin.androidLogger
import org.koin.core.context.startKoin
import org.koin.core.logger.Level
import org.koin.dsl.module

class App : Application() {
    override fun onCreate() {
        super.onCreate()

        val module = module {
            single {
                Katzrdum(
                    StringField(KEY_MESSAGE, getString(R.string.field_message)),
                    PasswordField(KEY_PASSWORD, getString(R.string.field_password)),
                    ColorField(KEY_BACKGROUND, getString(R.string.field_background), Color.BLACK),
                    LongIntegerField(KEY_FAV_NUMBER, getString(R.string.field_fav_number), 42)
                )
            }
        }

        startKoin {
            androidLogger(if (BuildConfig.DEBUG) Level.ERROR else Level.NONE)
            androidContext(this@App)
            modules(module)
        }
    }
}