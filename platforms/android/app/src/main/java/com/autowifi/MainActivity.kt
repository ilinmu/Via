package com.autowifi

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.result.contract.ActivityResultContracts
import androidx.activity.viewModels
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.core.content.ContextCompat
import com.autowifi.ui.AppViewModel
import com.autowifi.ui.AutoWifiApp

class MainActivity : ComponentActivity() {
    private val viewModel: AppViewModel by viewModels()
    private var permissionVersion by mutableIntStateOf(0)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            val version = permissionVersion
            val hasPermission = remember(version) { viewModel.hasPermissions() }

            val permissionLauncher = androidx.activity.compose.rememberLauncherForActivityResult(
                ActivityResultContracts.RequestMultiplePermissions(),
            ) {
                permissionVersion++
                viewModel.refreshCurrentSsid()
            }
            val notificationLauncher = androidx.activity.compose.rememberLauncherForActivityResult(
                ActivityResultContracts.RequestPermission(),
            ) { }

            androidx.compose.runtime.LaunchedEffect(Unit) {
                if (!viewModel.hasPermissions()) {
                    permissionLauncher.launch(requiredPermissions())
                }
            }

            AutoWifiApp(
                viewModel = viewModel,
                hasPermission = hasPermission,
                onRequestPermission = { permissionLauncher.launch(requiredPermissions()) },
                onRequestNotifications = {
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
                        ContextCompat.checkSelfPermission(
                            this,
                            Manifest.permission.POST_NOTIFICATIONS,
                        ) != PackageManager.PERMISSION_GRANTED
                    ) {
                        notificationLauncher.launch(Manifest.permission.POST_NOTIFICATIONS)
                    }
                },
                onOpenAppSettings = {
                    startActivity(
                        Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                            data = Uri.fromParts("package", packageName, null)
                        },
                    )
                },
            )
        }
    }

    override fun onResume() {
        super.onResume()
        permissionVersion++
        viewModel.refreshCurrentSsid()
        viewModel.ensureService()
    }

    private fun requiredPermissions(): Array<String> {
        val permissions = mutableListOf(
            Manifest.permission.ACCESS_FINE_LOCATION,
            Manifest.permission.ACCESS_COARSE_LOCATION,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            permissions += Manifest.permission.NEARBY_WIFI_DEVICES
        }
        return permissions.toTypedArray()
    }
}
