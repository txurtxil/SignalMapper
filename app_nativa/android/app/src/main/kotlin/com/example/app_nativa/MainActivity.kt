package com.example.app_nativa
import androidx.annotation.NonNull
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.Context
import android.telephony.*
import android.net.wifi.WifiManager
import android.os.Build

class MainActivity: FlutterActivity() {
    private val CHANNEL = "com.signalmapper/power_pro"
    override fun configureFlutterEngine(@NonNull flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "getCellularAudit" -> result.success(getCellularAudit())
                "getWifiAudit" -> result.success(getWifiAudit())
                else -> result.notImplemented()
            }
        }
    }
    private fun getCellularAudit(): Map<String, Any> {
        val tm = getSystemService(Context.TELEPHONY_SERVICE) as TelephonyManager
        val audit = mutableMapOf<String, Any>()
        audit["operator"] = tm.networkOperatorName ?: "Desconocido"
        audit["is_roaming"] = tm.isNetworkRoaming
        audit["dbm"] = -120
        audit["tech"] = "Buscando..."
        audit["cell_id"] = -1; audit["pci"] = -1; audit["tac"] = -1; audit["rsrq"] = 0; audit["snr"] = 0
        val cells = mutableListOf<Map<String, Any>>()
        try {
            val list = tm.allCellInfo
            if (!list.isNullOrEmpty()) {
                for (info in list) {
                    val c = mutableMapOf<String, Any>()
                    when (info) {
                        is CellInfoLte -> {
                            c["type"] = "LTE"; c["dbm"] = info.cellSignalStrength.dbm
                            c["rsrq"] = info.cellSignalStrength.rsrq; c["snr"] = info.cellSignalStrength.rssnr
                            c["cid"] = info.cellIdentity.ci; c["pci"] = info.cellIdentity.pci; c["tac"] = info.cellIdentity.tac
                            c["band"] = if (Build.VERSION.SDK_INT >= 24) info.cellIdentity.earfcn else -1
                        }
                        is CellInfoNr -> {
                            c["type"] = "NR"; val id = info.cellIdentity as? CellIdentityNr; val st = info.cellSignalStrength as? CellSignalStrengthNr
                            c["dbm"] = st?.dbm ?: -120; c["rsrq"] = st?.csiRsrq ?: 0; c["snr"] = st?.csiSinr ?: 0
                            c["cid"] = -1; c["pci"] = id?.pci ?: -1; c["tac"] = id?.tac ?: -1
                            c["band"] = if (Build.VERSION.SDK_INT >= 24) (id?.nrarfcn ?: -1) else -1
                        }
                        is CellInfoWcdma -> {
                            c["type"] = "WCDMA"; c["dbm"] = info.cellSignalStrength.dbm
                            c["rsrq"] = 0; c["snr"] = 0
                            c["cid"] = info.cellIdentity.cid; c["pci"] = -1; c["tac"] = info.cellIdentity.lac
                            c["band"] = if (Build.VERSION.SDK_INT >= 24) info.cellIdentity.uarfcn else -1
                        }
                        is CellInfoGsm -> {
                            c["type"] = "GSM"; c["dbm"] = info.cellSignalStrength.dbm
                            c["rsrq"] = 0; c["snr"] = 0
                            c["cid"] = info.cellIdentity.cid; c["pci"] = -1; c["tac"] = info.cellIdentity.lac
                            c["band"] = if (Build.VERSION.SDK_INT >= 24) info.cellIdentity.arfcn else -1
                        }
                        else -> continue
                    }
                    c["serving"] = info.isRegistered
                    cells.add(c)
                }
                val serving = cells.firstOrNull { it["serving"] == true }
                if (serving != null) {
                    audit["tech"] = when (serving["type"]) { "LTE" -> "4G (LTE)"; "NR" -> "5G (NR)"; "WCDMA" -> "3G (WCDMA)"; else -> "2G (GSM)" }
                    audit["dbm"] = serving["dbm"] as Int
                    audit["rsrq"] = serving["rsrq"] as Int; audit["snr"] = serving["snr"] as Int
                    audit["cell_id"] = (serving["cid"] as? Int) ?: -1
                    audit["pci"] = (serving["pci"] as? Int) ?: -1
                    audit["tac"] = (serving["tac"] as? Int) ?: -1
                }
            }
        } catch (e: Exception) { audit["tech"] = "Sensor Bloqueado" }
        audit["cells"] = cells
        return audit
    }
    private fun getWifiAudit(): Map<String, Any> {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val info = wifiManager.connectionInfo
        val audit = mutableMapOf<String, Any>()
        audit["dbm"] = info.rssi
        val ssid = info.ssid.replace("\"", "")
        audit["ssid"] = if (ssid == "<unknown ssid>") "¡Enciende el GPS para ver el nombre!" else ssid
        audit["bssid"] = info.bssid ?: "Unknown"
        audit["link_speed"] = info.linkSpeed
        val freq = info.frequency
        audit["freq_mhz"] = freq
        audit["band"] = if (freq in 2400..2500) "2.4 GHz (Lejos)" else if (freq in 5000..6000) "5 GHz (Rápido)" else "Desconocido"
        return audit
    }
}
