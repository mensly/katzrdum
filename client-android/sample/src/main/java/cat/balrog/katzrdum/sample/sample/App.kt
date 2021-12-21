package cat.balrog.katzrdum.sample.sample

import android.app.Application
import cat.balrog.katzrdum.Katzrdum
import cat.balrog.katzrdum.StringField
import org.koin.android.ext.koin.androidContext
import org.koin.android.ext.koin.androidLogger
import org.koin.core.context.startKoin
import org.koin.dsl.module

class App : Application() {
    override fun onCreate() {
        super.onCreate()

        val module = module {
            single { Katzrdum(StringField(KEY_MESSAGE)) }
        }

        startKoin {
            androidLogger()
            androidContext(this@App)
            modules(module)
        }
    }
}