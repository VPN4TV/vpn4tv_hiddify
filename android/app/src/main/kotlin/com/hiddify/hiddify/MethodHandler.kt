package com.hiddify.hiddify

import android.util.Log
import com.hiddify.hiddify.bg.BoxService
//import com.hiddify.hiddify.bg.BoxService.Companion.workingDir
import com.hiddify.hiddify.constant.Status
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

import com.hiddify.core.libbox.Libbox
import com.hiddify.core.mobile.Mobile
import com.hiddify.core.mobile.SetupOptions
import com.hiddify.hiddify.bg.Bugs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.GlobalScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.io.File

class MethodHandler(private val scope: CoroutineScope) : FlutterPlugin,
    MethodChannel.MethodCallHandler {
    private var channel: MethodChannel? = null

    companion object {
        const val TAG = "A/MethodHandler"
        const val channelName = "com.hiddify.app/method"

        enum class Trigger(val method: String) {
            Setup("setup"),
            Start("start"),
            Stop("stop"),
            Restart("restart"),
            AddGrpcClientPublicKey("add_grpc_client_public_key"),
            GetGrpcServerPublicKey("get_grpc_server_public_key"),

        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(
            flutterPluginBinding.binaryMessenger,
            channelName,
        )
        channel!!.setMethodCallHandler(this)
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel?.setMethodCallHandler(null)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            Trigger.AddGrpcClientPublicKey.method -> {
                GlobalScope.launch {
                    result.runCatching {
                        val args = call.arguments as Map<*, *>
                        val clientPub = args["clientPublicKey"] as ByteArray
//                        Mobile.addGrpcClientPublicKey(clientPub)
                        Settings.grpcFlutterPublicKey = clientPub
                        success("")

                    }
                }
            }

            Trigger.GetGrpcServerPublicKey.method -> {
                GlobalScope.launch {
                    result.runCatching {
                        result.success(Mobile.getServerPublicKey())
                    }
                }
            }

            Trigger.Setup.method -> {
                GlobalScope.launch {
                    result.runCatching {
                        val args = call.arguments as Map<*, *>
                        Settings.baseDir = args["baseDir"] as String
                        Settings.workingDir = args["workingDir"] as String
                        Settings.tempDir = args["tempDir"] as String
                        Settings.debugMode = args["debug"] as Boolean? ?: false
                        val mode = args["mode"] as Int
                        val grpcPort = args["grpcPort"] as Int
                        Log.d("debugmode","${Settings.debugMode}")
                        runCatching {
                            Mobile.setup(
                                SetupOptions().also {
                                    it.basePath = Settings.baseDir
                                    it.workingDir = Settings.workingDir
                                    it.tempDir = Settings.tempDir
                                    it.fixAndroidStack = Bugs.fixAndroidStack
                                    it.mode=mode.toLong()
                                    it.listen= "127.0.0.1:" + grpcPort
                                    it.secret=""
                                    it.debug = Settings.debugMode
                                },null)

//                            Libbox.setup(Settings.baseDir, Settings.workingDir, Settings.tempDir, false)
                            Libbox.redirectStderr(File(Settings.workingDir, "stderr2.log").path)

                            success("")
                        }.onFailure {
                            error(it)
                        }

                    }
                }
            }


            Trigger.Start.method -> {
                scope.launch {
                    result.runCatching {
                        val args = call.arguments as Map<*, *>
                        Settings.activeConfigPath = args["path"] as String? ?: ""
                        Settings.activeProfileName = args["name"] as String? ?: ""
                        Settings.debugMode = args["debug"] as Boolean? ?: false
                        Settings.grpcServiceModePort = args["grpcPort"] as Int

                        val mainActivity = MainActivity.instance
//                        val started = mainActivity.serviceStatus.value == Status.Started
//                        if (started) {
//                            Log.w(TAG, "service is already running")
//                            return@launch success(true)
//                        }
                        Settings.startCoreAfterStartingService = false

                        mainActivity.startService()
                        success(true)
                    }
                }
            }

            Trigger.Stop.method -> {
                scope.launch {
                    result.runCatching {
                        val mainActivity = MainActivity.instance
                        val started = mainActivity.serviceStatus.value == Status.Started
                        if (!started) {
                            Log.w(TAG, "service is not running")
                            //    return@launch success(true)
                        }
                        BoxService.stop()
                        success(true)
                    }
                }
            }

//            Trigger.Restart.method -> {
//                scope.launch(Dispatchers.IO) {
//                    result.runCatching {
//                        val args = call.arguments as Map<*, *>
//                        Settings.activeConfigPath = args["path"] as String? ?: ""
//                        Settings.activeProfileName = args["name"] as String? ?: ""
//                        val mainActivity = MainActivity.instance
//                        val started = mainActivity.serviceStatus.value == Status.Started
//                        if (!started) return@launch success(true)
//                        val restart = Settings.rebuildServiceMode()
//                        if (restart) {
//                            mainActivity.reconnect()
//                            BoxService.stop()
//                            delay(1000L)
//                            mainActivity.startService()
//                            return@launch success(true)
//                        }
//                        runCatching {
//                            Libbox.newStandaloneCommandClient().serviceReload()
//                            success(true)
//                        }.onFailure {
//                            error(it)
//                        }
//                    }
//                }
//            }

            "protect_socket" -> {
                // Protect a TCP socket by its local port so it bypasses VPN TUN.
                // Dart gRPC creates sockets to 127.0.0.1 that need protection
                // on multi-user Android TV devices where self-exclude isn't possible.
                scope.launch(Dispatchers.IO) {
                    result.runCatching {
                        val args = call.arguments as Map<*, *>
                        val localPort = args["localPort"] as Int
                        val vpn = com.hiddify.hiddify.bg.VPNService.instance
                        if (vpn == null) {
                            success(false)
                            return@launch
                        }
                        val protected = protectSocketByLocalPort(vpn, localPort)
                        success(protected)
                    }
                }
            }

            else -> result.notImplemented()
        }
    }

    /**
     * Find a TCP socket fd by its local port via /proc/self/net/tcp
     * and call VpnService.protect() on it.
     */
    private fun protectSocketByLocalPort(vpn: android.net.VpnService, localPort: Int): Boolean {
        try {
            val portHex = String.format("%04X", localPort)
            val tcpFile = java.io.File("/proc/self/net/tcp")
            if (!tcpFile.exists()) return false

            for (line in tcpFile.readLines().drop(1)) {
                val parts = line.trim().split("\\s+".toRegex())
                if (parts.size < 10) continue
                val localAddr = parts[1]
                // Match 0100007F:PORT (127.0.0.1) or 00000000:PORT (0.0.0.0)
                if (!localAddr.endsWith(":$portHex")) continue
                val ip = localAddr.split(":")[0]
                if (ip != "0100007F" && ip != "00000000") continue

                val inode = parts[9]
                if (inode == "0") continue

                val fdDir = java.io.File("/proc/self/fd")
                for (fd in fdDir.listFiles() ?: emptyArray()) {
                    try {
                        val link = java.nio.file.Files.readSymbolicLink(fd.toPath()).toString()
                        if (link == "socket:[$inode]") {
                            val fdNum = fd.name.toIntOrNull() ?: continue
                            vpn.protect(fdNum)
                            Log.d(TAG, "Protected socket fd=$fdNum port=$localPort inode=$inode")
                            return true
                        }
                    } catch (_: Throwable) {}
                }
            }
        } catch (e: Throwable) {
            Log.w(TAG, "protectSocketByLocalPort failed: ${e.message}")
        }
        return false
    }
}