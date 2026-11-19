import GObject from 'gi://GObject';
import Gio from 'gi://Gio';
import GLib from 'gi://GLib';

import * as Main from 'resource:///org/gnome/shell/ui/main.js';
import * as PopupMenu from 'resource:///org/gnome/shell/ui/popupMenu.js';
import * as QuickSettings from 'resource:///org/gnome/shell/ui/quickSettings.js';

import {Extension} from 'resource:///org/gnome/shell/extensions/extension.js';

const AIRPLAY_SCRIPT = GLib.build_filenamev([GLib.get_home_dir(), '.local', 'bin', 'compartir-tv']);
const AIRPLAY_LOG = GLib.build_filenamev([GLib.get_user_cache_dir(), 'compartir-tv.log']);
const CAST_APP_ID = 'org.gnome.NetworkDisplays';

const TvToggle = GObject.registerClass(
class TvToggle extends QuickSettings.QuickMenuToggle {
    _init() {
        super._init({
            title: 'Compartir TV',
            iconName: 'video-display-symbolic',
            toggleMode: true,
        });

        this._airplay = null;
        this._cast = null;
        this._stopping = false;
        this._syncing = false;
        this._launcher = new Gio.SubprocessLauncher({
            flags: Gio.SubprocessFlags.STDOUT_SILENCE |
                   Gio.SubprocessFlags.STDERR_SILENCE,
        });

        this.menu.setHeader('video-display-symbolic', 'Compartir pantalla');

        // Interruptor visible en el menú: es la forma más clara de encender y
        // apagar AirPlay sin depender del botón de la cuadrícula.
        this._airplayItem = new PopupMenu.PopupSwitchMenuItem('AirPlay', false);
        this._airplayItem.connect('toggled', (item, state) => {
            if (this._syncing)
                return;
            if (state)
                this._startAirPlay();
            else
                this._stopAirPlay();
        });
        this.menu.addMenuItem(this._airplayItem);

        this._status = new PopupMenu.PopupMenuItem('AirPlay: inactivo · Google Cast: cerrada', {reactive: false});
        this.menu.addMenuItem(this._status);

        this.menu.addMenuItem(new PopupMenu.PopupSeparatorMenuItem());

        this._castItem = new PopupMenu.PopupMenuItem('Abrir Google Cast');
        this._castItem.connect('activate', () => this._toggleCast());
        this.menu.addMenuItem(this._castItem);

        this.connect('clicked', () => {
            // No nos fiamos de this.checked: el estado real es el del proceso.
            if (this._airplay)
                this._stopAirPlay();
            else
                this._startAirPlay();
        });

        this.connect('destroy', () => this._stopAll());
    }

    _syncUi() {
        const active = !!this._airplay;
        const cast = !!this._cast;

        this._syncing = true;
        this.checked = active;
        this._airplayItem.setToggleState(active);
        this._syncing = false;

        this._status.label.text =
            `AirPlay: ${active ? 'activo' : 'inactivo'} · Google Cast: ${cast ? 'abierta' : 'cerrada'}`;
        this._castItem.label.text = cast ? 'Cerrar Google Cast' : 'Abrir Google Cast';
        this.subtitle = active ? 'Transmitiendo por AirPlay' : '';
    }

    _startAirPlay() {
        if (this._airplay) {
            this._syncUi();
            return;
        }

        this._stopping = false;

        try {
            // Redirigimos la salida a un log: gnome-shell silencia stdout y sin
            // esto no hay forma de saber por qué falla. `exec` mantiene el PID,
            // así que la señal de parada sigue llegando al proceso real.
            const cmd = `exec "${AIRPLAY_SCRIPT}" >>"${AIRPLAY_LOG}" 2>&1`;
            this._airplay = this._launcher.spawnv(['sh', '-c', cmd]);
        } catch (e) {
            this._airplay = null;
            this._syncUi();
            Main.notifyError('No se pudo iniciar AirPlay', e.message);
            return;
        }

        this._syncUi();

        this._airplay.wait_async(null, (proc, res) => {
            let ok = false;
            try {
                proc.wait_finish(res);
                ok = proc.get_successful();
            } catch (e) {
                ok = false;
            }

            const wasStopping = this._stopping;
            this._airplay = null;
            this._stopping = false;
            this._syncUi();

            if (!ok && !wasStopping) {
                Main.notifyError('AirPlay se detuvo',
                    `Revisa el motivo en ${AIRPLAY_LOG}`);
            }
        });
    }

    _stopAirPlay() {
        if (this._airplay) {
            this._stopping = true;
            this._airplay.send_signal(15);
            return;
        }
        this._syncUi();
    }

    _toggleCast() {
        if (this._cast) {
            this._cast.send_signal(15);
            return;
        }

        try {
            this._cast = this._launcher.spawnv(['flatpak', 'run', '--user', CAST_APP_ID]);
        } catch (e) {
            Main.notifyError('No se pudo abrir Google Cast', e.message);
            this._syncUi();
            return;
        }

        this._syncUi();

        this._cast.wait_async(null, (proc, res) => {
            try {
                proc.wait_finish(res);
            } catch (e) {
                // El proceso ya no existe: nada que hacer.
            }
            this._cast = null;
            this._syncUi();
        });
    }

    _stopAll() {
        if (this._airplay)
            this._airplay.send_signal(15);
        if (this._cast)
            this._cast.send_signal(15);
        this._airplay = null;
        this._cast = null;
    }
});

const TvIndicator = GObject.registerClass(
class TvIndicator extends QuickSettings.SystemIndicator {
    _init() {
        super._init();

        this._toggle = new TvToggle();
        this.quickSettingsItems.push(this._toggle);
    }

    destroy() {
        // GNOME reparenta los quickSettingsItems a la rejilla del menú rápido,
        // así que no son hijos de este indicador: hay que destruirlos a mano.
        // Si no, al desactivar la extensión el botón queda huérfano y al
        // volver a activarla aparece duplicado (p. ej. al bloquear la sesión).
        this.quickSettingsItems.forEach(item => item.destroy());
        super.destroy();
    }
});

export default class TvShareExtension extends Extension {
    enable() {
        log('[tv-share] build 5 cargado');
        this._indicator = new TvIndicator();
        Main.panel.statusArea.quickSettings.addExternalIndicator(this._indicator);
    }

    disable() {
        this._indicator?.destroy();
        this._indicator = null;
    }
}
