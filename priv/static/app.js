// The bridge's page: LiveView, and the one thing it cannot do from the
// server - point a camera at a QR code. Offered only where the browser can
// (BarcodeDetector, and a camera, which browsers give to https and to
// localhost only); pasting the link works everywhere.
(function () {
  const Scan = {
    mounted() {
      if (!("BarcodeDetector" in window) || !navigator.mediaDevices) return
      this.el.hidden = false
      this.el.addEventListener("click", () => this.scan())
    },
    async scan() {
      const video = document.getElementById("scan-video")
      const detector = new BarcodeDetector({ formats: ["qr_code"] })
      let stream
      try {
        stream = await navigator.mediaDevices.getUserMedia({ video: { facingMode: "environment" } })
      } catch (_e) {
        return
      }
      video.srcObject = stream
      video.hidden = false
      await video.play()
      const look = async () => {
        const codes = await detector.detect(video).catch(() => [])
        const link = codes.map((c) => c.rawValue).find((v) => /\/join\//.test(v))
        if (link) {
          stream.getTracks().forEach((t) => t.stop())
          video.hidden = true
          document.getElementById("join-link").value = link
          this.pushEvent("join", { link })
        } else {
          requestAnimationFrame(look)
        }
      }
      look()
    },
  }

  window.addEventListener("DOMContentLoaded", () => {
    const csrf = document.querySelector("meta[name='csrf-token']").getAttribute("content")
    const liveSocket = new LiveView.LiveSocket("/live", Phoenix.Socket, {
      params: { _csrf_token: csrf },
      hooks: { Scan },
    })
    liveSocket.connect()
  })
})()
