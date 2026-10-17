import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import * as DuskmoonHooks from "../../../../deps/phoenix_duskmoon/assets/js/hooks/index.js"

import {register as registerButton} from "@duskmoon-dev/el-button"
import {register as registerCard} from "@duskmoon-dev/el-card"
import {register as registerBadge} from "@duskmoon-dev/el-badge"
import {register as registerDialog} from "@duskmoon-dev/el-dialog"
import {register as registerAlert} from "@duskmoon-dev/el-alert"
import {register as registerPopover} from "@duskmoon-dev/el-popover"

registerButton()
registerCard()
registerBadge()
registerDialog()
registerAlert()
registerPopover()

import topbar from "../vendor/topbar"

const csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  params: {_csrf_token: csrfToken},
  hooks: DuskmoonHooks
})

// Close dialogs when buttons inside dialog forms are clicked
document.addEventListener("click", (event) => {
  const btn = event.target.closest("el-dm-button")
  if (btn) {
    const dialogForm = btn.closest("form[method='dialog']")
    if (dialogForm) {
      const dialog = dialogForm.closest("el-dm-dialog")
      if (dialog && typeof dialog.close === "function") {
        dialog.close()
      }
    }
  }
})

// Show progress bar on live navigation and form submits
topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()
window.liveSocket = liveSocket
