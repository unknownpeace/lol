#!/bin/sh
# ==============================================================================
# Установщик веб-интерфейса LuCI (luci-app-gateway) для OpenWrt >= 25.12.6
# ==============================================================================

install_openwrt_luci_app() {
    is_openwrt 2>/dev/null || return 0
    [ -d /usr/share/luci/menu.d ] || return 0

    SRC_LUCI="${GATEWAY_DIR}/modules/luci"
    [ -d "$SRC_LUCI" ] || return 0

    mkdir -p /usr/libexec/rpcd /usr/share/luci/menu.d /usr/share/rpcd/acl.d \
             /www/luci-static/resources/tools /www/luci-static/resources/view/gateway

    if [ -f "${SRC_LUCI}/rpcd/gateway" ]; then
        cp -f "${SRC_LUCI}/rpcd/gateway" /usr/libexec/rpcd/gateway
        chmod 755 /usr/libexec/rpcd/gateway
    fi

    if [ -f "${SRC_LUCI}/root/usr/share/luci/menu.d/luci-app-gateway.json" ]; then
        cp -f "${SRC_LUCI}/root/usr/share/luci/menu.d/luci-app-gateway.json" /usr/share/luci/menu.d/luci-app-gateway.json
        chmod 644 /usr/share/luci/menu.d/luci-app-gateway.json
    fi

    if [ -f "${SRC_LUCI}/root/usr/share/rpcd/acl.d/luci-app-gateway.json" ]; then
        cp -f "${SRC_LUCI}/root/usr/share/rpcd/acl.d/luci-app-gateway.json" /usr/share/rpcd/acl.d/luci-app-gateway.json
        chmod 644 /usr/share/rpcd/acl.d/luci-app-gateway.json
    fi

    if [ -f "${SRC_LUCI}/root/www/luci-static/resources/tools/gateway.js" ]; then
        cp -f "${SRC_LUCI}/root/www/luci-static/resources/tools/gateway.js" /www/luci-static/resources/tools/gateway.js
        chmod 644 /www/luci-static/resources/tools/gateway.js
    fi

    for JS_F in "${SRC_LUCI}"/root/www/luci-static/resources/view/gateway/*.js; do
        [ -f "$JS_F" ] || continue
        cp -f "$JS_F" "/www/luci-static/resources/view/gateway/$(basename "$JS_F")"
        chmod 644 "/www/luci-static/resources/view/gateway/$(basename "$JS_F")"
    done

    rm -rf /tmp/luci-indexcache* /tmp/luci-modulecache/* 2>/dev/null || true
    /etc/init.d/rpcd reload >/dev/null 2>&1 || /etc/init.d/rpcd restart >/dev/null 2>&1 || true
    return 0
}
