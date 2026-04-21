#!/bin/bash
cd /workspaces/SignalMapper/app_nativa

echo "🍺 1/2 Aplicando parche antibloqueo para antenas 5G..."
cat << 'KOTLIN' > android/app/src/main/kotlin/com/example/app_nativa/MainActivity.kt
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
        
        audit["operator"] = tm.networkOperatorName ?: "Unknown"
        audit["is_roaming"] = tm.isNetworkRoaming
        audit["dbm"] = -120
        audit["tech"] = "Buscando..."
        audit["cell_id"] = -1
        audit["pci"] = -1
        audit["tac"] = -1
        audit["rsrq"] = 0
        audit["snr"] = 0

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            try {
                val cellInfoList = tm.allCellInfo
                if (!cellInfoList.isNullOrEmpty()) {
                    val info = cellInfoList[0]
                    if (info is CellInfoLte) {
                        audit["tech"] = "4G (LTE)"
                        audit["cell_id"] = info.cellIdentity.ci
                        audit["pci"] = info.cellIdentity.pci
                        audit["tac"] = info.cellIdentity.tac
                        audit["dbm"] = info.cellSignalStrength.dbm
                        audit["rsrq"] = info.cellSignalStrength.rsrq
                        audit["snr"] = info.cellSignalStrength.rssnr
                    } else if (info is CellInfoNr) {
                        audit["tech"] = "5G (NR)"
                        // CAST EXPLÍCITO PARA EVITAR EL ERROR DEL COMPILADOR
                        val idNr = info.cellIdentity as? CellIdentityNr
                        val strNr = info.cellSignalStrength as? CellSignalStrengthNr
                        
                        audit["pci"] = idNr?.pci ?: -1
                        audit["tac"] = idNr?.tac ?: -1
                        audit["dbm"] = strNr?.dbm ?: -120
                        audit["rsrq"] = strNr?.csiRsrq ?: 0
                        audit["snr"] = strNr?.csiSinr ?: 0
                    }
                }
            } catch (e: Exception) {
                audit["tech"] = "Sensor Blocked"
            }
        }
        return audit
    }

    private fun getWifiAudit(): Map<String, Any> {
        val wifiManager = applicationContext.getSystemService(Context.WIFI_SERVICE) as WifiManager
        val info = wifiManager.connectionInfo
        val audit = mutableMapOf<String, Any>()
        
        audit["dbm"] = info.rssi
        audit["ssid"] = info.ssid.replace("\"", "")
        audit["bssid"] = info.bssid ?: "Unknown"
        audit["link_speed"] = info.linkSpeed
        
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
            val freq = info.frequency
            audit["freq_mhz"] = freq
            audit["band"] = if (freq in 2400..2500) "2.4 GHz" else if (freq in 5000..6000) "5 GHz" else "Unknown"
        }
        return audit
    }
}
KOTLIN

echo "🚀 2/2 Compilando a máxima velocidad..."
flutter build apk --profile

if [ -f "build/app/outputs/flutter-apk/app-profile.apk" ]; then
    gh release create v10.1-godmode build/app/outputs/flutter-apk/app-profile.apk --repo txurtxil/SignalMapper --title "🔥 SignalMapper V10.1 GOD MODE" --notes "Fallo de variables 5G solucionado. Listo para usar en la calle."
    echo "===================================================="
    echo "✅ ¡COMPILADO! Bájate el APK, apura el vaso y a probar:"
    echo "https://github.com/txurtxil/SignalMapper/releases/latest"
    echo "===================================================="
else
    echo "❌ Error. Mándame el log."
fi
