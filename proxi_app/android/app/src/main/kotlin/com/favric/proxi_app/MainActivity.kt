package com.favric.proxi_app

import android.Manifest
import android.content.pm.PackageManager
import androidx.core.uwb.RangingParameters
import androidx.core.uwb.RangingResult
import androidx.core.uwb.UwbComplexChannel
import androidx.core.uwb.UwbControleeSessionScope
import androidx.core.uwb.UwbControllerSessionScope
import androidx.core.uwb.UwbDevice
import androidx.core.uwb.UwbManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.launch

/**
 * Puente UWB entre Flutter (Dart) y Jetpack UWB (Android).
 *
 * NOTA: androidx.core:core-uwb está en alpha; su API puede cambiar entre versiones.
 * Este archivo es el ÚNICO que hay que iterar sobre el hardware real (2 equipos con UWB).
 * El intercambio de direcciones/canal entre los dos teléfonos lo hace Dart vía Firestore.
 */
class MainActivity : FlutterActivity() {

    private val methodName = "proxi/uwb"
    private val eventName = "proxi/uwb_events"

    private var events: EventChannel.EventSink? = null
    private val scope = CoroutineScope(Dispatchers.Main + SupervisorJob())
    private var rangingJob: Job? = null
    private var controllerScope: UwbControllerSessionScope? = null
    private var controleeScope: UwbControleeSessionScope? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Pide el permiso de UWB (y ubicación) al iniciar.
        if (checkSelfPermission(Manifest.permission.UWB_RANGING) != PackageManager.PERMISSION_GRANTED) {
            requestPermissions(
                arrayOf(Manifest.permission.UWB_RANGING, Manifest.permission.ACCESS_FINE_LOCATION),
                1001
            )
        }

        EventChannel(flutterEngine.dartExecutor.binaryMessenger, eventName).setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, sink: EventChannel.EventSink?) { events = sink }
                override fun onCancel(arguments: Any?) { events = null }
            }
        )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, methodName).setMethodCallHandler { call, result ->
            when (call.method) {
                "isAvailable" -> result.success(packageManager.hasSystemFeature(PackageManager.FEATURE_UWB))
                "prepareController" -> prepareController(result)
                "prepareControlee" -> prepareControlee(result)
                "startRanging" -> startRanging(call, result)
                "stop" -> { stopRanging(); result.success(true) }
                else -> result.notImplemented()
            }
        }
    }

    private fun manager() = UwbManager.createInstance(this)

    private fun prepareController(result: MethodChannel.Result) {
        scope.launch {
            try {
                val s = manager().controllerSessionScope()
                controllerScope = s
                result.success(
                    mapOf(
                        "address" to s.localAddress.address.map { it.toInt() and 0xFF },
                        "channel" to s.uwbComplexChannel.channel,
                        "preamble" to s.uwbComplexChannel.preambleIndex
                    )
                )
            } catch (e: Exception) {
                result.error("UWB", e.message, null)
            }
        }
    }

    private fun prepareControlee(result: MethodChannel.Result) {
        scope.launch {
            try {
                val s = manager().controleeSessionScope()
                controleeScope = s
                result.success(
                    mapOf("address" to s.localAddress.address.map { it.toInt() and 0xFF })
                )
            } catch (e: Exception) {
                result.error("UWB", e.message, null)
            }
        }
    }

    private fun startRanging(call: MethodCall, result: MethodChannel.Result) {
        val role = call.argument<String>("role")
        val peer = (call.argument<List<Int>>("peerAddress") ?: emptyList()).map { it.toByte() }.toByteArray()
        val sessionId = call.argument<Int>("sessionId") ?: 0
        val key = (call.argument<List<Int>>("sessionKey") ?: emptyList()).map { it.toByte() }.toByteArray()
        val channel = call.argument<Int>("channel") ?: 9
        val preamble = call.argument<Int>("preamble") ?: 10

        val params = RangingParameters(
            uwbConfigType = RangingParameters.CONFIG_UNICAST_DS_TWR,
            sessionId = sessionId,
            subSessionId = 0,
            sessionKeyInfo = key,
            subSessionKeyInfo = null,
            complexChannel = UwbComplexChannel(channel, preamble),
            peerDevices = listOf(UwbDevice.createForAddress(peer)),
            updateRateType = RangingParameters.RANGING_UPDATE_RATE_AUTOMATIC
        )

        val session = if (role == "controller") controllerScope else controleeScope
        if (session == null) {
            result.error("UWB", "session not prepared (llama prepareController/prepareControlee primero)", null)
            return
        }

        rangingJob?.cancel()
        rangingJob = scope.launch {
            try {
                session.prepareSession(params).collect { r ->
                    when (r) {
                        is RangingResult.RangingResultPosition -> {
                            val pos = r.position
                            events?.success(
                                mapOf(
                                    "type" to "position",
                                    "distance" to pos.distance?.value,   // metros
                                    "azimuth" to pos.azimuth?.value,      // grados
                                    "elevation" to pos.elevation?.value
                                )
                            )
                        }
                        is RangingResult.RangingResultPeerDisconnected ->
                            events?.success(mapOf("type" to "disconnected"))
                        else -> {}
                    }
                }
            } catch (e: Exception) {
                events?.success(mapOf("type" to "error", "message" to e.message))
            }
        }
        result.success(true)
    }

    private fun stopRanging() {
        rangingJob?.cancel()
        rangingJob = null
        controllerScope = null
        controleeScope = null
    }

    override fun onDestroy() {
        stopRanging()
        scope.cancel()
        super.onDestroy()
    }
}
