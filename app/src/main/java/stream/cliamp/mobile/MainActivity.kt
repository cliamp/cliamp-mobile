package stream.cliamp.mobile

import android.Manifest
import android.os.Build
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.core.view.WindowCompat
import androidx.media3.common.util.UnstableApi
import stream.cliamp.mobile.ui.CliampRoot
import stream.cliamp.mobile.ui.theme.CliampTheme

@UnstableApi
class MainActivity : ComponentActivity() {

    private val permissions = registerForActivityResult(
        ActivityResultContracts.RequestMultiplePermissions()
    ) { }

    override fun onCreate(savedInstanceState: Bundle?) {
        enableEdgeToEdge()
        super.onCreate(savedInstanceState)
        WindowCompat.setDecorFitsSystemWindows(window, false)

        val app = application as CliampApp
        app.player.connect()

        val wanted = buildList {
            // the Visualizer taps the output mix, which the platform treats as
            // a recording capability whether or not a mic is involved
            add(Manifest.permission.RECORD_AUDIO)
            if (Build.VERSION.SDK_INT >= 33) add(Manifest.permission.POST_NOTIFICATIONS)
        }
        permissions.launch(wanted.toTypedArray())

        setContent {
            val palette by app.prefs.palette.collectAsState(initial = "dark")
            val dark = when (palette) {
                "light" -> false
                "system" -> resources.configuration.uiMode and
                    android.content.res.Configuration.UI_MODE_NIGHT_MASK ==
                    android.content.res.Configuration.UI_MODE_NIGHT_YES
                else -> true
            }
            val haptics by app.prefs.haptics.collectAsState(initial = true)
            // the platform draws the clock and battery, so it needs telling
            // which way the ground went
            androidx.compose.runtime.LaunchedEffect(dark) {
                WindowCompat.getInsetsController(window, window.decorView).apply {
                    isAppearanceLightStatusBars = !dark
                    isAppearanceLightNavigationBars = !dark
                }
            }
            CliampTheme(dark = dark, haptics = haptics) {
                CliampRoot(
                    repository = app.repository,
                    prefs = app.prefs,
                    player = app.player,
                    localLibrary = app.localLibrary,
                    playlists = app.playlists,
                    dark = dark,
                )
            }
        }
    }
}
