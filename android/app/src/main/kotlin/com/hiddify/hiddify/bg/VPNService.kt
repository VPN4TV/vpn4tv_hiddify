package com.hiddify.hiddify.bg
import android.util.Log

import com.hiddify.hiddify.Settings
import android.content.Context
import android.content.Intent
import android.net.ProxyInfo
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.UserManager
import com.hiddify.core.libbox.Notification
import com.hiddify.hiddify.constant.PerAppProxyMode
import com.hiddify.hiddify.ktx.toIpPrefix
import com.hiddify.core.libbox.TunOptions
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withContext
import java.io.File

class VPNService : VpnService(), PlatformInterfaceWrapper {

    companion object {
        private const val TAG = "A/VPNService"
        // Expose instance for protect_socket MethodChannel calls
        @Volatile var instance: VPNService? = null
    }

    init {
        instance = this
    }

    private val service = BoxService(this, this)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int) =
        service.onStartCommand()

    override fun onBind(intent: Intent): IBinder {
        val binder = super.onBind(intent)
        if (binder != null) {
            return binder
        }
        return service.onBind(intent)
    }

    override fun onDestroy() {
        service.onDestroy()
    }

    override fun onRevoke() {
        runBlocking {
            withContext(Dispatchers.Main) {
                service.onRevoke()
            }
        }
    }

    override fun autoDetectInterfaceControl(fd: Int) {
        protect(fd)
    }

    var systemProxyAvailable = false
    var systemProxyEnabled = false

    /**
     * Detect if device has multiple user profiles (restricted profiles).
     * On such devices, addDisallowedApplication() triggers SIGABRT via
     * getPackageUid + INTERACT_ACROSS_USERS. Skip self-exclude on these devices.
     */
    private fun hasMultipleUserProfiles(): Boolean {
        return try {
            val userManager = getSystemService(Context.USER_SERVICE) as? UserManager
            val profiles = userManager?.userProfiles ?: emptyList()
            val result = profiles.size > 1
            if (result) Log.i(TAG, "Multi-user device detected (${profiles.size} profiles) — skipping self-exclude")
            result
        } catch (e: Throwable) {
            Log.w(TAG, "Failed to check user profiles: ${e.message}")
            false
        }
    }

    /**
     * Protect TCP sockets connected to 127.0.0.1 by reading /proc/self/net/tcp.
     * This prevents gRPC connections from being routed through the VPN TUN.
     * Called after establish() when self-exclude is not used.
     */
    private fun protectLoopbackSockets() {
        try {
            val tcpFile = File("/proc/self/net/tcp")
            if (!tcpFile.exists()) return

            val lines = tcpFile.readLines().drop(1) // skip header
            val fdDir = File("/proc/self/fd")

            for (line in lines) {
                val parts = line.trim().split("\\s+".toRegex())
                if (parts.size < 10) continue

                val localAddr = parts[1] // e.g. "0100007F:3039"
                val addrParts = localAddr.split(":")
                if (addrParts.size != 2) continue

                // 0100007F = 127.0.0.1 in little-endian hex
                val ip = addrParts[0]
                if (ip != "0100007F") continue

                val inode = parts[9]
                if (inode == "0") continue

                // Find fd with this inode in /proc/self/fd
                val fds = fdDir.listFiles() ?: continue
                for (fd in fds) {
                    try {
                        val link = java.nio.file.Files.readSymbolicLink(fd.toPath()).toString()
                        if (link == "socket:[$inode]") {
                            val fdNum = fd.name.toIntOrNull() ?: continue
                            protect(fdNum)
                            Log.d(TAG, "Protected loopback socket fd=$fdNum inode=$inode")
                        }
                    } catch (_: Throwable) {}
                }
            }
        } catch (e: Throwable) {
            Log.w(TAG, "Failed to protect loopback sockets: ${e.message}")
        }
    }

    fun addIncludePackage(builder: Builder, packageName: String) {
        if (packageName == this.packageName) {
            Log.d(TAG, "Cannot include myself: $packageName")
            return
        }
        try {
            Log.d(TAG, "Including $packageName")
            builder.addAllowedApplication(packageName)
        } catch (e: Throwable) {
            Log.w(TAG, "Failed to include $packageName: ${e.message}")
        }
    }

    fun addExcludePackage(builder: Builder, packageName: String) {
        try {
            Log.d(TAG, "Excluding $packageName")
            builder.addDisallowedApplication(packageName)
        } catch (e: Throwable) {
            Log.w(TAG, "Failed to exclude $packageName: ${e.message}")
        }
    }

    /** Cached data from one-shot TunOptions iterators */
    private data class CachedTunData(
        val inet4Addresses: List<Pair<String, Int>>,
        val inet6Addresses: List<Pair<String, Int>>,
        val mtu: Int,
        val autoRoute: Boolean,
        val dnsServer: String,
        val inet4Routes: List<Any>,       // IpPrefix on API 33+, else Pair<String,Int>
        val inet6Routes: List<Any>,
        val inet4RouteExcludes: List<Any>, // IpPrefix on API 33+
        val inet6RouteExcludes: List<Any>,
        val includePackages: List<String>,
        val excludePackages: List<String>,
        val isHTTPProxyEnabled: Boolean,
        val httpProxyServer: String,
        val httpProxyServerPort: Int,
    )

    private fun cacheTunOptions(options: TunOptions): CachedTunData {
        val inet4Addr = mutableListOf<Pair<String, Int>>()
        val it4a = options.inet4Address
        while (it4a.hasNext()) { val a = it4a.next(); inet4Addr.add(a.address() to a.prefix()) }

        val inet6Addr = mutableListOf<Pair<String, Int>>()
        val it6a = options.inet6Address
        while (it6a.hasNext()) { val a = it6a.next(); inet6Addr.add(a.address() to a.prefix()) }

        val inet4Routes = mutableListOf<Any>()
        val inet6Routes = mutableListOf<Any>()
        val inet4Excludes = mutableListOf<Any>()
        val inet6Excludes = mutableListOf<Any>()

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            val it4r = options.inet4RouteAddress
            while (it4r.hasNext()) { inet4Routes.add(it4r.next().toIpPrefix()) }
            val it6r = options.inet6RouteAddress
            while (it6r.hasNext()) { inet6Routes.add(it6r.next().toIpPrefix()) }
            val it4e = options.inet4RouteExcludeAddress
            while (it4e.hasNext()) { inet4Excludes.add(it4e.next().toIpPrefix()) }
            val it6e = options.inet6RouteExcludeAddress
            while (it6e.hasNext()) { inet6Excludes.add(it6e.next().toIpPrefix()) }
        } else {
            val it4r = options.inet4RouteRange
            while (it4r.hasNext()) { val a = it4r.next(); inet4Routes.add(a.address() to a.prefix()) }
            val it6r = options.inet6RouteRange
            while (it6r.hasNext()) { val a = it6r.next(); inet6Routes.add(a.address() to a.prefix()) }
        }

        val includePkgs = mutableListOf<String>()
        val itIncl = options.includePackage
        while (itIncl.hasNext()) { includePkgs.add(itIncl.next()) }

        val excludePkgs = mutableListOf<String>()
        val itExcl = options.excludePackage
        while (itExcl.hasNext()) { excludePkgs.add(itExcl.next()) }

        return CachedTunData(
            inet4Addresses = inet4Addr,
            inet6Addresses = inet6Addr,
            mtu = options.mtu,
            autoRoute = options.autoRoute,
            dnsServer = options.dnsServerAddress.value,
            inet4Routes = inet4Routes,
            inet6Routes = inet6Routes,
            inet4RouteExcludes = inet4Excludes,
            inet6RouteExcludes = inet6Excludes,
            includePackages = includePkgs,
            excludePackages = excludePkgs,
            isHTTPProxyEnabled = options.isHTTPProxyEnabled,
            httpProxyServer = if (options.isHTTPProxyEnabled) options.httpProxyServer else "",
            httpProxyServerPort = if (options.isHTTPProxyEnabled) options.httpProxyServerPort else 0,
        )
    }

    @Suppress("UNCHECKED_CAST")
    private fun buildVpnInterface(data: CachedTunData, excludeSelf: Boolean): ParcelFileDescriptor {
        val builder = Builder()
            .setSession("hiddify")
            .setMtu(data.mtu)

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            builder.setMetered(false)
        }

        for ((addr, prefix) in data.inet4Addresses) {
            builder.addAddress(addr, prefix)
        }
        for ((addr, prefix) in data.inet6Addresses) {
            builder.addAddress(addr, prefix)
        }

        if (data.autoRoute) {
            builder.addDnsServer(data.dnsServer)

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                if (data.inet4Routes.isNotEmpty()) {
                    for (route in data.inet4Routes) {
                        builder.addRoute(route as android.net.IpPrefix)
                    }
                } else {
                    builder.addRoute("0.0.0.0", 0)
                }

                if (data.inet6Routes.isNotEmpty()) {
                    for (route in data.inet6Routes) {
                        builder.addRoute(route as android.net.IpPrefix)
                    }
                } else {
                    builder.addRoute("::", 0)
                }

                for (route in data.inet4RouteExcludes) {
                    builder.excludeRoute(route as android.net.IpPrefix)
                }
                for (route in data.inet6RouteExcludes) {
                    builder.excludeRoute(route as android.net.IpPrefix)
                }
            } else {
                for (route in data.inet4Routes) {
                    val (addr, prefix) = route as Pair<String, Int>
                    builder.addRoute(addr, prefix)
                }
                for (route in data.inet6Routes) {
                    val (addr, prefix) = route as Pair<String, Int>
                    builder.addRoute(addr, prefix)
                }
            }

            if (Settings.perAppProxyEnabled) {
                val appList = Settings.perAppProxyList
                if (Settings.perAppProxyMode == PerAppProxyMode.INCLUDE) {
                    appList.forEach { addIncludePackage(builder, it) }
                } else {
                    appList.forEach { addExcludePackage(builder, it) }
                    if (excludeSelf) addExcludePackage(builder, packageName)
                }
            } else {
                if (data.includePackages.isNotEmpty()) {
                    data.includePackages.forEach { addIncludePackage(builder, it) }
                }
                if (data.excludePackages.isNotEmpty()) {
                    data.excludePackages.forEach { addExcludePackage(builder, it) }
                }
                if (excludeSelf) addExcludePackage(builder, packageName)
            }

            if (!excludeSelf && Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                // Fallback for INTERACT_ACROSS_USERS devices: can't exclude self,
                // so explicitly exclude loopback from TUN to keep gRPC on 127.0.0.1 working
                try {
                    builder.excludeRoute(android.net.IpPrefix(java.net.InetAddress.getByName("127.0.0.0"), 8))
                    Log.i(TAG, "Excluded loopback from TUN for gRPC fallback")
                } catch (e: Throwable) {
                    Log.w(TAG, "Failed to exclude loopback: ${e.message}")
                }
            }
        }

        if (data.isHTTPProxyEnabled && Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            systemProxyAvailable = true
            systemProxyEnabled = Settings.systemProxyEnabled
            if (systemProxyEnabled) builder.setHttpProxy(
                ProxyInfo.buildDirectProxy(data.httpProxyServer, data.httpProxyServerPort)
            )
        } else {
            systemProxyAvailable = false
            systemProxyEnabled = false
        }

        return builder.establish()
            ?: error("android: the application is not prepared or is revoked")
    }

    override fun openTun(options: TunOptions): Int {
        var hasPermission = false
        for (i in 0 until 20) {
            if (prepare(this) != null) {
                Log.w(TAG, "android: missing vpn permission")
            } else {
                hasPermission = true
                break
            }
            Thread.sleep(50)
        }

        if (!hasPermission) {
            error("android: missing vpn permission")
        }

        // Cache all data from one-shot iterators so we can retry
        val data = cacheTunOptions(options)

        // Multi-user devices (Sony Bravia, Hisense, TCL with restricted profiles)
        // SIGABRT when addDisallowedApplication calls getPackageUid.
        // On these devices, skip self-exclude and protect gRPC sockets instead.
        val isMultiUser = hasMultipleUserProfiles()

        val pfd = if (isMultiUser) {
            val result = buildVpnInterface(data, excludeSelf = false)
            // Protect existing gRPC sockets so they bypass TUN
            protectLoopbackSockets()
            result
        } else {
            try {
                buildVpnInterface(data, excludeSelf = true)
            } catch (e: Throwable) {
                Log.w(TAG, "establish() failed with self-exclusion, retrying without: ${e.message}")
                val result = buildVpnInterface(data, excludeSelf = false)
                protectLoopbackSockets()
                result
            }
        }

        service.fileDescriptor = pfd
        return pfd.fd
    }

//    override fun writeLog(message: String) = service.writeLog(message)

    override fun sendNotification(notification: Notification) {
//        service.sendNotification(notification)
    }
}
