package com.autowifi.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.ArrowDropDown
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.filled.Refresh
import androidx.compose.material.icons.filled.Visibility
import androidx.compose.material.icons.filled.VisibilityOff
import androidx.compose.material.icons.filled.Wifi
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.DropdownMenuItem
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.ExposedDropdownMenuBox
import androidx.compose.material3.ExposedDropdownMenuDefaults
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.LinearProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.MenuAnchorType
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Surface
import androidx.compose.material3.Switch
import androidx.compose.material3.Tab
import androidx.compose.material3.TabRow
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.text.input.VisualTransformation
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import com.autowifi.BuildConfig
import com.autowifi.service.MonitorState
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun AutoWifiApp(
    viewModel: AppViewModel,
    hasPermission: Boolean,
    onRequestPermission: () -> Unit,
    onRequestNotifications: () -> Unit,
    onOpenAppSettings: () -> Unit,
) {
    AutoWifiTheme {
        val state by viewModel.monitor.collectAsState()
        Surface(
            modifier = Modifier.fillMaxSize(),
            color = MaterialTheme.colorScheme.background,
        ) {
            if (viewModel.showWizard) {
                SetupWizard(
                    viewModel = viewModel,
                    hasPermission = hasPermission,
                    onRequestPermission = onRequestPermission,
                    onRequestNotifications = onRequestNotifications,
                    onOpenAppSettings = onOpenAppSettings,
                )
            } else {
                MainTabs(
                    viewModel = viewModel,
                    state = state,
                    hasPermission = hasPermission,
                    onRequestPermission = onRequestPermission,
                    onRequestNotifications = onRequestNotifications,
                    onOpenAppSettings = onOpenAppSettings,
                )
            }
        }
    }
}

@Composable
private fun MainTabs(
    viewModel: AppViewModel,
    state: MonitorState,
    hasPermission: Boolean,
    onRequestPermission: () -> Unit,
    onRequestNotifications: () -> Unit,
    onOpenAppSettings: () -> Unit,
) {
    // Tabs are pages so they can also be swiped; the tab row and the pager
    // share the same current page.
    val pagerState = rememberPagerState(pageCount = { 3 })
    val scope = rememberCoroutineScope()
    val focusManager = LocalFocusManager.current
    // Do not leave an input focused after switching pages; a focused text field
    // captures drags and blocks the pager.
    LaunchedEffect(pagerState.currentPage) { focusManager.clearFocus() }
    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding(),
    ) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = viewModel.t("app_name"),
                style = MaterialTheme.typography.titleMedium,
            )
        }

        TabRow(selectedTabIndex = pagerState.currentPage) {
            listOf("tab_status", "tab_networks", "tab_settings").forEachIndexed { index, key ->
                Tab(
                    selected = pagerState.currentPage == index,
                    onClick = {
                        scope.launch { pagerState.animateScrollToPage(index) }
                    },
                    text = { Text(viewModel.t(key)) },
                )
            }
        }

        HorizontalPager(
            state = pagerState,
            // Keep neighbouring pages composed so their scroll position and
            // scan results survive a swipe.
            beyondViewportPageCount = 2,
            modifier = Modifier.weight(1f),
        ) { page ->
            when (page) {
                0 -> StatusTab(
                    viewModel = viewModel,
                    state = state,
                    hasPermission = hasPermission,
                    onRequestPermission = onRequestPermission,
                    onRequestNotifications = onRequestNotifications,
                    onOpenAppSettings = onOpenAppSettings,
                )
                1 -> NetworksTab(viewModel = viewModel, hasPermission = hasPermission)
                else -> SettingsTab(
                    viewModel = viewModel,
                    state = state,
                    hasPermission = hasPermission,
                    onRequestPermission = onRequestPermission,
                    onOpenAppSettings = onOpenAppSettings,
                )
            }
        }
    }
}

@Composable
private fun StatusTab(
    viewModel: AppViewModel,
    state: MonitorState,
    hasPermission: Boolean,
    onRequestPermission: () -> Unit,
    onRequestNotifications: () -> Unit,
    onOpenAppSettings: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        if (!hasPermission) {
            PermissionCard(
                viewModel = viewModel,
                onRequestPermission = onRequestPermission,
                onOpenAppSettings = onOpenAppSettings,
            )
        }

        ConnectionCard(viewModel = viewModel, state = state, hasPermission = hasPermission)

        Card(
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant,
            ),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth().padding(16.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(modifier = Modifier.weight(1f)) {
                    Text(
                        text = viewModel.t("auto_switch"),
                        style = MaterialTheme.typography.titleSmall,
                        fontWeight = FontWeight.SemiBold,
                    )
                    Spacer(Modifier.height(4.dp))
                    Text(
                        text = viewModel.t("auto_switch_hint"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
                Spacer(Modifier.width(12.dp))
                Switch(
                    checked = state.running,
                    enabled = hasPermission,
                    onCheckedChange = { wanted ->
                        if (wanted) {
                            onRequestNotifications()
                            viewModel.startMonitoring()
                        } else {
                            viewModel.stopMonitoring()
                        }
                    },
                )
            }
        }

        if (state.running && state.nextCheckAtMs > 0L) {
            val formatter = remember { SimpleDateFormat("HH:mm:ss", Locale.getDefault()) }
            Text(
                text = "${viewModel.t("status_next_check")} · " +
                    formatter.format(Date(state.nextCheckAtMs)),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        state.lastEvent?.let { event ->
            Text(
                text = viewModel.eventName(event),
                style = MaterialTheme.typography.bodyMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            OutlinedButton(onClick = { viewModel.checkNow() }, enabled = state.running) {
                Icon(Icons.Filled.Refresh, contentDescription = null, modifier = Modifier.size(18.dp))
                Spacer(Modifier.width(6.dp))
                Text(viewModel.t("status_check_now"))
            }
            OutlinedButton(onClick = { viewModel.refreshCurrentSsid() }) {
                Text(viewModel.t("status_refresh"))
            }
        }

        Text(
            text = viewModel.t("status_android_note"),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun ConnectionCard(
    viewModel: AppViewModel,
    state: MonitorState,
    hasPermission: Boolean,
) {
    val statusColor: Color
    val statusLabel: String
    if (!hasPermission) {
        statusColor = MaterialTheme.colorScheme.error
        statusLabel = viewModel.t("status_waiting_permission")
    } else if (state.running) {
        statusColor = MaterialTheme.colorScheme.primary
        statusLabel = viewModel.t("status_running")
    } else {
        statusColor = MaterialTheme.colorScheme.onSurfaceVariant
        statusLabel = viewModel.t("status_paused")
    }

    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.surfaceVariant,
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
            Text(
                text = viewModel.t("status_title"),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
            Spacer(Modifier.height(6.dp))
            Text(
                text = state.currentSsid ?: viewModel.currentSsid
                    ?: viewModel.t("status_not_connected"),
                style = MaterialTheme.typography.titleLarge,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Spacer(Modifier.height(8.dp))
            Row(verticalAlignment = Alignment.CenterVertically) {
                Box(
                    modifier = Modifier
                        .size(8.dp)
                        .background(statusColor, CircleShape),
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    text = statusLabel,
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            if (state.currentSsid != null && state.role != "none") {
                Spacer(Modifier.height(4.dp))
                Text(
                    text = com.autowifi.L10n.role(state.role, viewModel.language),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@Composable
private fun PermissionCard(
    viewModel: AppViewModel,
    onRequestPermission: () -> Unit,
    onOpenAppSettings: () -> Unit,
) {
    Card(
        colors = CardDefaults.cardColors(
            containerColor = MaterialTheme.colorScheme.errorContainer.copy(alpha = 0.4f),
        ),
        modifier = Modifier.fillMaxWidth(),
    ) {
        Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
            Text(
                text = viewModel.t("status_permission_banner"),
                style = MaterialTheme.typography.bodyMedium,
            )
            Spacer(Modifier.height(12.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Button(onClick = onRequestPermission) {
                    Text(viewModel.t("grant_permission"))
                }
                TextButton(onClick = onOpenAppSettings) {
                    Text(viewModel.t("open_settings"))
                }
            }
        }
    }
}

@Composable
private fun NetworksTab(viewModel: AppViewModel, hasPermission: Boolean) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = viewModel.t("networks_hint"),
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Row(verticalAlignment = Alignment.CenterVertically) {
            OutlinedButton(
                onClick = { viewModel.scan() },
                enabled = hasPermission && !viewModel.isScanning,
            ) {
                if (viewModel.isScanning) {
                    CircularProgressIndicator(
                        modifier = Modifier.size(16.dp),
                        strokeWidth = 2.dp,
                    )
                } else {
                    Icon(Icons.Filled.Wifi, contentDescription = null, modifier = Modifier.size(18.dp))
                }
                Spacer(Modifier.width(6.dp))
                Text(
                    viewModel.t(if (viewModel.isScanning) "scanning" else "scan_networks"),
                )
            }
            if (!hasPermission) {
                Spacer(Modifier.width(12.dp))
                Text(
                    text = viewModel.t("scan_needs_permission"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        viewModel.scanMessage?.let { key ->
            Text(
                text = viewModel.t(key),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        if (viewModel.scanResults.isNotEmpty()) {
            Text(
                text = com.autowifi.L10n.tf(
                    "networks_found",
                    viewModel.language,
                    viewModel.scanResults.size,
                ),
                style = MaterialTheme.typography.labelMedium,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        NetworkEditor(
            viewModel = viewModel,
            title = viewModel.t("priority_network"),
            ssid = viewModel.ssidP,
            onSsidChange = { viewModel.ssidP = it },
            password = viewModel.passwordP,
            onPasswordChange = { viewModel.passwordP = it },
            currentSsid = viewModel.currentSsid,
            onUseCurrent = { viewModel.useCurrentNetwork(primary = true) },
            networks = viewModel.scanResults,
            scanning = viewModel.isScanning,
            onScan = { viewModel.scan() },
        )

        NetworkEditor(
            viewModel = viewModel,
            title = viewModel.t("backup_network"),
            ssid = viewModel.ssidB,
            onSsidChange = { viewModel.ssidB = it },
            password = viewModel.passwordB,
            onPasswordChange = { viewModel.passwordB = it },
            currentSsid = viewModel.currentSsid,
            onUseCurrent = { viewModel.useCurrentNetwork(primary = false) },
            networks = viewModel.scanResults,
            scanning = viewModel.isScanning,
            onScan = { viewModel.scan() },
        )

        viewModel.saveError?.let { key ->
            Text(
                text = viewModel.t(key),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.error,
            )
        }

        Row(verticalAlignment = Alignment.CenterVertically) {
            Button(onClick = { viewModel.save() }) {
                Text(viewModel.t("save_changes"))
            }
            Spacer(Modifier.width(12.dp))
            if (viewModel.savedOnce && viewModel.saveError == null) {
                Text(
                    text = viewModel.t("saved"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class, ExperimentalComposeUiApi::class)
@Composable
private fun NetworkEditor(
    viewModel: AppViewModel,
    title: String,
    ssid: String,
    onSsidChange: (String) -> Unit,
    password: String,
    onPasswordChange: (String) -> Unit,
    currentSsid: String?,
    onUseCurrent: () -> Unit,
    networks: List<String>,
    scanning: Boolean,
    onScan: () -> Unit,
) {
    var visible by remember { mutableStateOf(false) }
    var expanded by remember { mutableStateOf(false) }
    val focusManager = LocalFocusManager.current
    val keyboard = LocalSoftwareKeyboardController.current
    // A focused text field swallows horizontal drags for text selection, which
    // keeps the pager from scrolling; drop focus once a value is picked.
    fun releaseInputFocus() {
        focusManager.clearFocus()
        keyboard?.hide()
    }
    Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
        Text(
            text = title,
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
        )
        // The SSID field doubles as a dropdown of the last scan, so a network
        // is picked in place instead of through a separate P/B list.
        ExposedDropdownMenuBox(
            expanded = expanded,
            onExpandedChange = { expanded = !expanded },
        ) {
            OutlinedTextField(
                value = ssid,
                onValueChange = onSsidChange,
                label = { Text(viewModel.t("ssid_label")) },
                singleLine = true,
                trailingIcon = {
                    ExposedDropdownMenuDefaults.TrailingIcon(expanded = expanded)
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .menuAnchor(MenuAnchorType.PrimaryEditable),
            )
            ExposedDropdownMenu(
                expanded = expanded,
                onDismissRequest = {
                    expanded = false
                    releaseInputFocus()
                },
            ) {
                if (networks.isEmpty()) {
                    DropdownMenuItem(
                        text = { Text(viewModel.t("scan_first")) },
                        onClick = { expanded = false },
                        enabled = false,
                    )
                } else {
                    networks.forEach { option ->
                        DropdownMenuItem(
                            text = { Text(option) },
                            onClick = {
                                onSsidChange(option)
                                releaseInputFocus()
                                expanded = false
                            },
                        )
                    }
                }
                HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                // Scan and use-current share one row at the bottom of the list
                // so scanning does not require scrolling back to the top.
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = 4.dp, vertical = 2.dp),
                    verticalAlignment = Alignment.CenterVertically,
                ) {
                    if (currentSsid != null) {
                        TextButton(
                            onClick = {
                                onUseCurrent()
                                releaseInputFocus()
                                expanded = false
                            },
                            modifier = Modifier.widthIn(max = 190.dp),
                        ) {
                            Text(
                                text = "${viewModel.t("use_current")} · $currentSsid",
                                style = MaterialTheme.typography.labelLarge,
                                maxLines = 1,
                                overflow = TextOverflow.Ellipsis,
                            )
                        }
                    }
                    Spacer(Modifier.weight(1f))
                    TextButton(
                        onClick = {
                            releaseInputFocus()
                            onScan()
                            expanded = false
                        },
                        enabled = !scanning,
                    ) {
                        if (scanning) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(14.dp),
                                strokeWidth = 2.dp,
                            )
                        } else {
                            Icon(
                                imageVector = Icons.Filled.Wifi,
                                contentDescription = null,
                                modifier = Modifier.size(16.dp),
                            )
                        }
                        Spacer(Modifier.width(6.dp))
                        Text(
                            text = viewModel.t(if (scanning) "scanning" else "scan_networks"),
                            style = MaterialTheme.typography.labelLarge,
                        )
                    }
                }
            }
        }
        OutlinedTextField(
            value = password,
            onValueChange = onPasswordChange,
            label = { Text(viewModel.t("password")) },
            singleLine = true,
            visualTransformation = if (visible) {
                VisualTransformation.None
            } else {
                PasswordVisualTransformation()
            },
            trailingIcon = {
                IconButton(onClick = { visible = !visible }) {
                    Icon(
                        imageVector = if (visible) Icons.Filled.VisibilityOff else Icons.Filled.Visibility,
                        contentDescription = viewModel.t(
                            if (visible) "hide_password" else "show_password",
                        ),
                    )
                }
            },
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/**
 * Deliberately as short as [CompactNumberField] so the language row matches the
 * check-interval row below it instead of using a full-height Material field.
 */
@Composable
private fun LanguageDropdown(viewModel: AppViewModel) {
    var expanded by remember { mutableStateOf(false) }
    val current = if (viewModel.language == "en") "English" else "中文"
    Box(modifier = Modifier.width(140.dp)) {
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .height(36.dp)
                .border(
                    width = 1.dp,
                    color = MaterialTheme.colorScheme.outline,
                    shape = RoundedCornerShape(8.dp),
                )
                .clickable { expanded = true }
                .padding(horizontal = 12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                text = current,
                style = MaterialTheme.typography.bodyMedium,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f),
            )
            Icon(
                imageVector = Icons.Filled.ArrowDropDown,
                contentDescription = null,
                tint = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }
        DropdownMenu(
            expanded = expanded,
            onDismissRequest = { expanded = false },
        ) {
            listOf("zh" to "中文", "en" to "English").forEach { (value, text) ->
                DropdownMenuItem(
                    text = { Text(text) },
                    onClick = {
                        viewModel.chooseLanguage(value)
                        expanded = false
                    },
                )
            }
        }
    }
}

/**
 * The interval field is deliberately shorter than a Material text field so the
 * label, input and unit fit on one line.
 */
@Composable
private fun CompactNumberField(
    value: String,
    onValueChange: (String) -> Unit,
    onCommit: () -> Unit,
) {
    BasicTextField(
        value = value,
        onValueChange = onValueChange,
        singleLine = true,
        textStyle = MaterialTheme.typography.bodyMedium.copy(
            color = MaterialTheme.colorScheme.onSurface,
            textAlign = TextAlign.Center,
        ),
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Number),
        modifier = Modifier
            .width(72.dp)
            .height(36.dp)
            .border(
                width = 1.dp,
                color = MaterialTheme.colorScheme.outline,
                shape = RoundedCornerShape(8.dp),
            )
            .onFocusChanged { focus ->
                if (!focus.isFocused) onCommit()
            },
        decorationBox = { inner ->
            Box(
                modifier = Modifier.fillMaxSize().padding(horizontal = 8.dp),
                contentAlignment = Alignment.Center,
            ) {
                inner()
            }
        },
    )
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun SettingsTab(
    viewModel: AppViewModel,
    state: MonitorState,
    hasPermission: Boolean,
    onRequestPermission: () -> Unit,
    onOpenAppSettings: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Text(
            text = viewModel.t("general"),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
        )

        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = viewModel.t("language"),
                modifier = Modifier.weight(1f),
                style = MaterialTheme.typography.bodyMedium,
            )
            LanguageDropdown(viewModel)
        }

        Column(verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Text(
                    text = viewModel.t("check_frequency"),
                    modifier = Modifier.weight(1f),
                    style = MaterialTheme.typography.bodyMedium,
                )
                CompactNumberField(
                    value = viewModel.intervalText,
                    onValueChange = { viewModel.onIntervalChanged(it) },
                    onCommit = { viewModel.commitInterval() },
                )
                Spacer(Modifier.width(8.dp))
                Text(
                    text = viewModel.t("seconds_unit"),
                    style = MaterialTheme.typography.bodyMedium,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
            Text(
                text = viewModel.t("interval_hint"),
                style = MaterialTheme.typography.bodySmall,
                color = MaterialTheme.colorScheme.onSurfaceVariant,
            )
        }

        Row(verticalAlignment = Alignment.CenterVertically) {
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    text = viewModel.t("start_on_boot"),
                    style = MaterialTheme.typography.bodyMedium,
                )
            }
            Switch(
                checked = viewModel.launchAtBoot,
                onCheckedChange = { viewModel.updateLaunchAtBoot(it) },
            )
        }

        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

        Text(
            text = viewModel.t("permissions_title"),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
        )
        Row(verticalAlignment = Alignment.CenterVertically) {
            Icon(
                imageVector = Icons.Filled.CheckCircle,
                contentDescription = null,
                tint = if (hasPermission) {
                    MaterialTheme.colorScheme.primary
                } else {
                    MaterialTheme.colorScheme.onSurfaceVariant
                },
                modifier = Modifier.size(18.dp),
            )
            Spacer(Modifier.width(8.dp))
            Text(
                text = viewModel.t(
                    if (hasPermission) "permission_granted" else "permission_denied",
                ),
                style = MaterialTheme.typography.bodyMedium,
                modifier = Modifier.weight(1f),
            )
            if (!hasPermission) {
                TextButton(onClick = onRequestPermission) {
                    Text(viewModel.t("grant_permission"))
                }
            }
            TextButton(onClick = onOpenAppSettings) {
                Text(viewModel.t("open_settings"))
            }
        }

        Card(
            colors = CardDefaults.cardColors(
                containerColor = MaterialTheme.colorScheme.surfaceVariant,
            ),
            modifier = Modifier.fillMaxWidth(),
        ) {
            Column(modifier = Modifier.fillMaxWidth().padding(16.dp)) {
                Text(
                    text = viewModel.t("android_limits"),
                    style = MaterialTheme.typography.titleSmall,
                    fontWeight = FontWeight.SemiBold,
                )
                Spacer(Modifier.height(6.dp))
                Text(
                    text = viewModel.t("android_limits_body"),
                    style = MaterialTheme.typography.bodySmall,
                    color = MaterialTheme.colorScheme.onSurfaceVariant,
                )
            }
        }

        TextButton(onClick = { viewModel.rerunWizard() }) {
            Text(viewModel.t("rerun_setup"))
        }

        if (state.running) {
            OutlinedButton(onClick = { viewModel.stopMonitoring() }) {
                Text(viewModel.t("stop_monitoring"))
            }
        }

        HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)

        Text(
            text = viewModel.t("about"),
            style = MaterialTheme.typography.titleSmall,
            fontWeight = FontWeight.SemiBold,
        )
        Text(
            text = "${viewModel.t("version")} ${BuildConfig.VERSION_NAME}",
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Text(
            text = viewModel.t("privacy"),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
    }
}

@Composable
private fun SetupWizard(
    viewModel: AppViewModel,
    hasPermission: Boolean,
    onRequestPermission: () -> Unit,
    onRequestNotifications: () -> Unit,
    onOpenAppSettings: () -> Unit,
) {
    val step = viewModel.wizardStep
    Column(
        modifier = Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(24.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            Text(
                text = viewModel.t("app_name"),
                style = MaterialTheme.typography.titleLarge,
            )
            Spacer(Modifier.weight(1f))
            TextButton(onClick = { viewModel.skipWizard() }) {
                Text(viewModel.t("wizard_skip"))
            }
        }
        Spacer(Modifier.height(12.dp))
        LinearProgressIndicator(
            progress = { (step + 1) / 3f },
            modifier = Modifier.fillMaxWidth(),
        )
        Spacer(Modifier.height(8.dp))
        Text(
            text = com.autowifi.L10n.tf("wizard_step", viewModel.language, step + 1),
            style = MaterialTheme.typography.bodySmall,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )

        Column(
            modifier = Modifier
                .weight(1f)
                .verticalScroll(rememberScrollState())
                .padding(vertical = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            when (step) {
                0 -> {
                    Text(
                        text = viewModel.t("wizard_permission_title"),
                        style = MaterialTheme.typography.headlineSmall,
                    )
                    Text(
                        text = viewModel.t("wizard_permission_body"),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    if (hasPermission) {
                        Row(verticalAlignment = Alignment.CenterVertically) {
                            Icon(
                                Icons.Filled.CheckCircle,
                                contentDescription = null,
                                tint = MaterialTheme.colorScheme.primary,
                            )
                            Spacer(Modifier.width(8.dp))
                            Text(viewModel.t("permission_granted"))
                        }
                    } else {
                        Button(onClick = onRequestPermission) {
                            Text(viewModel.t("grant_permission"))
                        }
                        TextButton(onClick = onOpenAppSettings) {
                            Text(viewModel.t("open_settings"))
                        }
                    }
                }
                1 -> {
                    Text(
                        text = viewModel.t("wizard_networks_title"),
                        style = MaterialTheme.typography.headlineSmall,
                    )
                    Text(
                        text = viewModel.t("wizard_networks_body"),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        OutlinedButton(
                            onClick = { viewModel.scan() },
                            enabled = hasPermission && !viewModel.isScanning,
                        ) {
                            if (viewModel.isScanning) {
                                CircularProgressIndicator(
                                    modifier = Modifier.size(16.dp),
                                    strokeWidth = 2.dp,
                                )
                            } else {
                                Icon(
                                    Icons.Filled.Wifi,
                                    contentDescription = null,
                                    modifier = Modifier.size(18.dp),
                                )
                            }
                            Spacer(Modifier.width(6.dp))
                            Text(
                                viewModel.t(if (viewModel.isScanning) "scanning" else "scan_networks"),
                            )
                        }
                        if (!hasPermission) {
                            Spacer(Modifier.width(12.dp))
                            Text(
                                text = viewModel.t("scan_needs_permission"),
                                style = MaterialTheme.typography.bodySmall,
                                color = MaterialTheme.colorScheme.onSurfaceVariant,
                            )
                        }
                    }
                    viewModel.scanMessage?.let { key ->
                        Text(
                            text = viewModel.t(key),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.onSurfaceVariant,
                        )
                    }
                    NetworkEditor(
                        viewModel = viewModel,
                        title = viewModel.t("priority_network"),
                        ssid = viewModel.ssidP,
                        onSsidChange = { viewModel.ssidP = it },
                        password = viewModel.passwordP,
                        onPasswordChange = { viewModel.passwordP = it },
                        currentSsid = viewModel.currentSsid,
                        onUseCurrent = { viewModel.useCurrentNetwork(primary = true) },
                        networks = viewModel.scanResults,
                        scanning = viewModel.isScanning,
                        onScan = { viewModel.scan() },
                    )
                    NetworkEditor(
                        viewModel = viewModel,
                        title = viewModel.t("backup_network"),
                        ssid = viewModel.ssidB,
                        onSsidChange = { viewModel.ssidB = it },
                        password = viewModel.passwordB,
                        onPasswordChange = { viewModel.passwordB = it },
                        currentSsid = viewModel.currentSsid,
                        onUseCurrent = { viewModel.useCurrentNetwork(primary = false) },
                        networks = viewModel.scanResults,
                        scanning = viewModel.isScanning,
                        onScan = { viewModel.scan() },
                    )
                    viewModel.saveError?.let { key ->
                        Text(
                            text = viewModel.t(key),
                            style = MaterialTheme.typography.bodySmall,
                            color = MaterialTheme.colorScheme.error,
                        )
                    }
                }
                else -> {
                    Text(
                        text = viewModel.t("wizard_finish_title"),
                        style = MaterialTheme.typography.headlineSmall,
                    )
                    Text(
                        text = viewModel.t("wizard_finish_body"),
                        style = MaterialTheme.typography.bodyMedium,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                    SummaryRow(viewModel.t("priority_network"), viewModel.ssidP)
                    SummaryRow(viewModel.t("backup_network"), viewModel.ssidB)
                    SummaryRow(
                        viewModel.t("permissions_title"),
                        viewModel.t(
                            if (hasPermission) "permission_granted" else "permission_denied",
                        ),
                    )
                    if (!hasPermission) {
                        Button(onClick = onRequestPermission) {
                            Text(viewModel.t("grant_permission"))
                        }
                    }
                    Text(
                        text = viewModel.t("privacy"),
                        style = MaterialTheme.typography.bodySmall,
                        color = MaterialTheme.colorScheme.onSurfaceVariant,
                    )
                }
            }
        }

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(12.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (step > 0) {
                OutlinedButton(onClick = { viewModel.goToStep(step - 1) }) {
                    Text(viewModel.t("wizard_back"))
                }
            }
            Spacer(Modifier.weight(1f))
            when (step) {
                0 -> Button(onClick = { viewModel.goToStep(1) }) {
                    Text(viewModel.t("wizard_next"))
                }
                1 -> Button(onClick = { viewModel.goToStep(2) }) {
                    Text(viewModel.t("wizard_next"))
                }
                else -> {
                    TextButton(onClick = { viewModel.finishWizard(start = false) }) {
                        Text(viewModel.t("wizard_save_only"))
                    }
                    Button(
                        onClick = {
                            onRequestNotifications()
                            viewModel.finishWizard(start = true)
                        },
                        enabled = hasPermission,
                    ) {
                        Text(viewModel.t("wizard_start"))
                    }
                }
            }
        }
    }
}

@Composable
private fun SummaryRow(label: String, value: String) {
    Row(
        modifier = Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(
            text = label,
            style = MaterialTheme.typography.bodyMedium,
            color = MaterialTheme.colorScheme.onSurfaceVariant,
        )
        Spacer(Modifier.weight(1f))
        Text(
            text = value.ifBlank { "—" },
            style = MaterialTheme.typography.bodyMedium,
            fontWeight = FontWeight.Medium,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
    }
}
