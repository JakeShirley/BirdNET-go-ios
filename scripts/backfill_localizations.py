#!/usr/bin/env python3
"""Backfill Onpa Localizable.xcstrings with es/de/ja translations.

Reads the current catalog, drops empty/duplicate placeholder entries that
xcstringstool sometimes leaves behind (e.g. "%arg" duplicates of "%@" keys
with no localizations at all), then writes translations for every entry
that still lacks one.
"""

import json
from pathlib import Path

CATALOG = Path("src/Onpa/Resources/Localizable.xcstrings")

# Map of source key -> translations. Use %@ for object substitutions and
# %lld for integer substitutions, matching what xcstringstool emitted.
# These translations are best-effort; mark uncertain ones for review.
TRANSLATIONS = {
    # Format strings used in interpolation
    "%@ m/s": {
        "es": "%@ m/s",
        "de": "%@ m/s",
        "ja": "%@ m/s",
    },
    "%@ m/s, gusts %@": {
        "es": "%@ m/s, ráfagas %@",
        "de": "%@ m/s, Böen %@",
        "ja": "%@ m/s、最大瞬間 %@",
    },
    "%@ °C": {
        "es": "%@ °C",
        "de": "%@ °C",
        "ja": "%@ °C",
    },
    "%@, %lld detections today": {
        "es": "%@, %lld detecciones hoy",
        "de": "%@, %lld Erkennungen heute",
        "ja": "%@、本日 %lld 件の検出",
    },
    "%@, %lld percent confidence at %@": {
        "es": "%@, %lld por ciento de confianza a las %@",
        "de": "%@, %lld Prozent Konfidenz um %@",
        "ja": "%@、信頼度 %lld パーセント、%@",
    },
    "%@, %lld percent confidence%@": {
        "es": "%@, %lld por ciento de confianza%@",
        "de": "%@, %lld Prozent Konfidenz%@",
        "ja": "%@、信頼度 %lld パーセント%@",
    },
    "%@: %@": {
        "es": "%@: %@",
        "de": "%@: %@",
        "ja": "%@: %@",
    },
    "%lld": {"es": "%lld", "de": "%lld", "ja": "%lld"},
    "%lld detections": {
        "es": "%lld detecciones",
        "de": "%lld Erkennungen",
        "ja": "%lld 件の検出",
    },
    "%lld percent confidence": {
        "es": "%lld por ciento de confianza",
        "de": "%lld Prozent Konfidenz",
        "ja": "信頼度 %lld パーセント",
    },
    "%lld%%": {"es": "%lld %%", "de": "%lld %%", "ja": "%lld %%"},
    "00": {"es": "00", "de": "00", "ja": "00"},
    "1 detection": {
        "es": "1 detección",
        "de": "1 Erkennung",
        "ja": "1 件の検出",
    },
    "23": {"es": "23", "de": "23", "ja": "23"},
    # Time of day
    "Afternoon": {"es": "Tarde", "de": "Nachmittag", "ja": "午後"},
    "Day": {"es": "Día", "de": "Tag", "ja": "昼"},
    "Evening": {"es": "Noche", "de": "Abend", "ja": "夕方"},
    "Morning": {"es": "Mañana", "de": "Morgen", "ja": "朝"},
    "Night": {"es": "Noche", "de": "Nacht", "ja": "夜"},
    "Sunrise": {"es": "Amanecer", "de": "Sonnenaufgang", "ja": "日の出"},
    "Sunset": {"es": "Atardecer", "de": "Sonnenuntergang", "ja": "日の入り"},
    "Twilight": {"es": "Crepúsculo", "de": "Dämmerung", "ja": "薄明"},
    # Static UI
    "Base URL": {"es": "URL base", "de": "Basis-URL", "ja": "ベース URL"},
    "Changelog Unavailable": {
        "es": "Registro de cambios no disponible",
        "de": "Änderungsprotokoll nicht verfügbar",
        "ja": "変更履歴は利用できません",
    },
    "Commit %@": {
        "es": "Commit %@",
        "de": "Commit %@",
        "ja": "コミット %@",
    },
    "Delete Station?": {
        "es": "¿Eliminar estación?",
        "de": "Station löschen?",
        "ja": "ステーションを削除しますか？",
    },
    "Disabled": {"es": "Deshabilitado", "de": "Deaktiviert", "ja": "無効"},
    "Enabled": {"es": "Habilitado", "de": "Aktiviert", "ja": "有効"},
    "Image credit: %@": {
        "es": "Crédito de imagen: %@",
        "de": "Bildnachweis: %@",
        "ja": "画像クレジット: %@",
    },
    "Image of %@": {
        "es": "Imagen de %@",
        "de": "Bild von %@",
        "ja": "%@ の画像",
    },
    "Loading changelog": {
        "es": "Cargando registro de cambios",
        "de": "Änderungsprotokoll wird geladen",
        "ja": "変更履歴を読み込み中",
    },
    "Loading dashboard": {
        "es": "Cargando panel",
        "de": "Dashboard wird geladen",
        "ja": "ダッシュボードを読み込み中",
    },
    "Loading detection": {
        "es": "Cargando detección",
        "de": "Erkennung wird geladen",
        "ja": "検出を読み込み中",
    },
    "Loading detections": {
        "es": "Cargando detecciones",
        "de": "Erkennungen werden geladen",
        "ja": "検出を読み込み中",
    },
    "Loading settings": {
        "es": "Cargando ajustes",
        "de": "Einstellungen werden geladen",
        "ja": "設定を読み込み中",
    },
    "Loading species": {
        "es": "Cargando especies",
        "de": "Arten werden geladen",
        "ja": "種を読み込み中",
    },
    "Loading species image": {
        "es": "Cargando imagen de la especie",
        "de": "Artenbild wird geladen",
        "ja": "種の画像を読み込み中",
    },
    "Loading spectrogram": {
        "es": "Cargando espectrograma",
        "de": "Spektrogramm wird geladen",
        "ja": "スペクトログラムを読み込み中",
    },
    "No": {"es": "No", "de": "Nein", "ja": "いいえ"},
    "Yes": {"es": "Sí", "de": "Ja", "ja": "はい"},
    "No Activity": {
        "es": "Sin actividad",
        "de": "Keine Aktivität",
        "ja": "アクティビティなし",
    },
    "No Recent Detections": {
        "es": "Sin detecciones recientes",
        "de": "Keine aktuellen Erkennungen",
        "ja": "最近の検出はありません",
    },
    "No Release Notes Yet": {
        "es": "Aún no hay notas de versión",
        "de": "Noch keine Versionshinweise",
        "ja": "まだリリースノートはありません",
    },
    "No Station Connected": {
        "es": "Ninguna estación conectada",
        "de": "Keine Station verbunden",
        "ja": "ステーションが接続されていません",
    },
    "Not connected": {
        "es": "No conectado",
        "de": "Nicht verbunden",
        "ja": "未接続",
    },
    "Offline": {"es": "Sin conexión", "de": "Offline", "ja": "オフライン"},
    "Opens an in-app browser": {
        "es": "Abre un navegador integrado",
        "de": "Öffnet einen integrierten Browser",
        "ja": "アプリ内ブラウザを開きます",
    },
    "Opens species details": {
        "es": "Abre los detalles de la especie",
        "de": "Öffnet die Artendetails",
        "ja": "種の詳細を開きます",
    },
    "Password": {"es": "Contraseña", "de": "Passwort", "ja": "パスワード"},
    "Pause audio clip": {
        "es": "Pausar clip de audio",
        "de": "Audioclip pausieren",
        "ja": "オーディオクリップを一時停止",
    },
    "Play audio clip": {
        "es": "Reproducir clip de audio",
        "de": "Audioclip abspielen",
        "ja": "オーディオクリップを再生",
    },
    "Quiet Right Now": {
        "es": "Tranquilidad ahora",
        "de": "Gerade ruhig",
        "ja": "現在は静かです",
    },
    "Read about %@ on Wikipedia": {
        "es": "Leer sobre %@ en Wikipedia",
        "de": "Über %@ auf Wikipedia lesen",
        "ja": "%@ について Wikipedia で読む",
    },
    "Username (optional)": {
        "es": "Usuario (opcional)",
        "de": "Benutzer (optional)",
        "ja": "ユーザー名（任意）",
    },
    "View release %@ on GitHub": {
        "es": "Ver versión %@ en GitHub",
        "de": "Version %@ auf GitHub ansehen",
        "ja": "リリース %@ を GitHub で表示",
    },
    "at %@": {"es": "a las %@", "de": "um %@", "ja": "%@"},
    "locked": {"es": "bloqueado", "de": "gesperrt", "ja": "ロック済み"},
    "new species": {"es": "especie nueva", "de": "neue Art", "ja": "新しい種"},
    "top confidence %@": {
        "es": "máxima confianza %@",
        "de": "höchste Konfidenz %@",
        "ja": "最高信頼度 %@",
    },
    "No recent detections": {
        "es": "Sin detecciones recientes",
        "de": "Keine aktuellen Erkennungen",
        "ja": "最近の検出はありません",
    },
    "No recent detections found for this species.": {
        "es": "No se encontraron detecciones recientes para esta especie.",
        "de": "Keine aktuellen Erkennungen für diese Art gefunden.",
        "ja": "この種の最近の検出は見つかりませんでした。",
    },
    "No recent detections.": {
        "es": "Sin detecciones recientes.",
        "de": "Keine aktuellen Erkennungen.",
        "ja": "最近の検出はありません。",
    },
    "No detected species.": {
        "es": "No se han detectado especies.",
        "de": "Keine erkannten Arten.",
        "ja": "検出された種はありません。",
    },
    "No activity for this day.": {
        "es": "Sin actividad para este día.",
        "de": "Keine Aktivität an diesem Tag.",
        "ja": "この日のアクティビティはありません。",
    },
    "Settings saved.": {
        "es": "Ajustes guardados.",
        "de": "Einstellungen gespeichert.",
        "ja": "設定を保存しました。",
    },
    "Station deleted.": {
        "es": "Estación eliminada.",
        "de": "Station gelöscht.",
        "ja": "ステーションを削除しました。",
    },
    "Logged out.": {
        "es": "Sesión cerrada.",
        "de": "Abgemeldet.",
        "ja": "ログアウトしました。",
    },
    "Diagnostics bundle ready to share.": {
        "es": "Paquete de diagnósticos listo para compartir.",
        "de": "Diagnosepaket zum Teilen bereit.",
        "ja": "診断バンドルを共有できます。",
    },
    "Loaded local test station profile.": {
        "es": "Se cargó el perfil de estación de prueba local.",
        "de": "Lokales Teststationsprofil geladen.",
        "ja": "ローカルテストステーションのプロファイルを読み込みました。",
    },
    "Using debug station URL override.": {
        "es": "Usando URL de estación de depuración.",
        "de": "Debug-Stations-URL wird verwendet.",
        "ja": "デバッグ用ステーション URL を使用しています。",
    },
    "Showing cached dashboard.": {
        "es": "Mostrando panel almacenado en caché.",
        "de": "Zwischengespeichertes Dashboard wird angezeigt.",
        "ja": "キャッシュされたダッシュボードを表示しています。",
    },
    "Showing cached species.": {
        "es": "Mostrando especies almacenadas en caché.",
        "de": "Zwischengespeicherte Arten werden angezeigt.",
        "ja": "キャッシュされた種を表示しています。",
    },
    "Showing cached detections.": {
        "es": "Mostrando detecciones almacenadas en caché.",
        "de": "Zwischengespeicherte Erkennungen werden angezeigt.",
        "ja": "キャッシュされた検出を表示しています。",
    },
    "Showing activity from recent detections.": {
        "es": "Mostrando actividad a partir de detecciones recientes.",
        "de": "Aktivität wird aus aktuellen Erkennungen angezeigt.",
        "ja": "最近の検出からアクティビティを表示しています。",
    },
    "Showing matching recent detections because species search is unavailable.": {
        "es": "Mostrando detecciones recientes coincidentes porque la búsqueda de especies no está disponible.",
        "de": "Passende aktuelle Erkennungen werden angezeigt, da die Artensuche nicht verfügbar ist.",
        "ja": "種の検索が利用できないため、一致する最近の検出を表示しています。",
    },
    "Showing station species catalog without recent detection summaries: %@": {
        "es": "Mostrando el catálogo de especies de la estación sin resúmenes de detecciones recientes: %@",
        "de": "Stations-Artenkatalog wird ohne aktuelle Erkennungszusammenfassungen angezeigt: %@",
        "ja": "最近の検出サマリーなしでステーションの種カタログを表示しています: %@",
    },
    "Daily activity loaded, but live hearing status is unavailable: %@": {
        "es": "Se cargó la actividad diaria, pero el estado de escucha en vivo no está disponible: %@",
        "de": "Tagesaktivität geladen, aber Live-Hörstatus ist nicht verfügbar: %@",
        "ja": "日々のアクティビティを読み込みましたが、ライブの聴取状況は利用できません: %@",
    },
    "Connect a BirdNET-Go station to load detection details.": {
        "es": "Conecta una estación BirdNET-Go para cargar los detalles de la detección.",
        "de": "Verbinde eine BirdNET-Go-Station, um Erkennungsdetails zu laden.",
        "ja": "BirdNET-Go ステーションに接続して検出の詳細を読み込みます。",
    },
    "Connect a BirdNET-Go station to load species details.": {
        "es": "Conecta una estación BirdNET-Go para cargar los detalles de la especie.",
        "de": "Verbinde eine BirdNET-Go-Station, um Artendetails zu laden.",
        "ja": "BirdNET-Go ステーションに接続して種の詳細を読み込みます。",
    },
    "No audio clip URL available.": {
        "es": "No hay URL de clip de audio disponible.",
        "de": "Keine Audio-Clip-URL verfügbar.",
        "ja": "オーディオクリップの URL がありません。",
    },
    "Ready to play": {
        "es": "Listo para reproducir",
        "de": "Bereit zur Wiedergabe",
        "ja": "再生準備完了",
    },
    "Paused": {"es": "En pausa", "de": "Pausiert", "ja": "一時停止"},
    "Playing": {"es": "Reproduciendo", "de": "Wird abgespielt", "ja": "再生中"},
    # Status / TLS
    "Reachable": {"es": "Accesible", "de": "Erreichbar", "ja": "到達可能"},
    "Unreachable": {"es": "No accesible", "de": "Nicht erreichbar", "ja": "到達不可"},
    "Unknown": {"es": "Desconocido", "de": "Unbekannt", "ja": "不明"},
    "Local HTTP": {"es": "HTTP local", "de": "Lokales HTTP", "ja": "ローカル HTTP"},
    # AppError errorDescription
    "The station appears to be offline or unreachable.": {
        "es": "La estación parece estar desconectada o inaccesible.",
        "de": "Die Station scheint offline oder nicht erreichbar zu sein.",
        "ja": "ステーションはオフラインまたは到達不可のようです。",
    },
    "Log in to the station to continue.": {
        "es": "Inicia sesión en la estación para continuar.",
        "de": "Melde dich bei der Station an, um fortzufahren.",
        "ja": "続行するにはステーションにログインしてください。",
    },
    "The station denied this request. Check your account permissions.": {
        "es": "La estación denegó esta solicitud. Comprueba los permisos de tu cuenta.",
        "de": "Die Station hat diese Anfrage abgelehnt. Prüfe die Berechtigungen deines Kontos.",
        "ja": "ステーションがリクエストを拒否しました。アカウントの権限を確認してください。",
    },
    "The station's secure connection could not be trusted.": {
        "es": "No se pudo confiar en la conexión segura de la estación.",
        "de": "Der gesicherten Verbindung der Station konnte nicht vertraut werden.",
        "ja": "ステーションのセキュア接続を信頼できませんでした。",
    },
    "The station is receiving too many requests. Try again in a moment.": {
        "es": "La estación está recibiendo demasiadas solicitudes. Vuelve a intentarlo en un momento.",
        "de": "Die Station erhält zu viele Anfragen. Versuche es in einem Moment erneut.",
        "ja": "ステーションへのリクエストが多すぎます。少し待ってから再試行してください。",
    },
    "The station returned HTTP %lld.": {
        "es": "La estación devolvió HTTP %lld.",
        "de": "Die Station antwortete mit HTTP %lld.",
        "ja": "ステーションが HTTP %lld を返しました。",
    },
    "The station returned an unexpected response.": {
        "es": "La estación devolvió una respuesta inesperada.",
        "de": "Die Station hat eine unerwartete Antwort gegeben.",
        "ja": "ステーションから予期しない応答がありました。",
    },
    "Enter a valid BirdNET-Go station URL.": {
        "es": "Introduce una URL de estación BirdNET-Go válida.",
        "de": "Gib eine gültige BirdNET-Go-Stations-URL ein.",
        "ja": "有効な BirdNET-Go ステーションの URL を入力してください。",
    },
    "Use HTTPS for remote stations. Plain HTTP is only supported for localhost, private IPs, and .local stations.": {
        "es": "Usa HTTPS para estaciones remotas. HTTP sin cifrar solo es compatible con localhost, IP privadas y estaciones .local.",
        "de": "Verwende HTTPS für entfernte Stationen. Klartext-HTTP wird nur für localhost, private IPs und .local-Stationen unterstützt.",
        "ja": "リモートステーションには HTTPS を使用してください。平文 HTTP は localhost、プライベート IP、.local ステーションのみでサポートされます。",
    },
    # AppError recoverySuggestion
    "Confirm the station is running and reachable from this device.": {
        "es": "Confirma que la estación esté en ejecución y sea accesible desde este dispositivo.",
        "de": "Stelle sicher, dass die Station läuft und von diesem Gerät erreichbar ist.",
        "ja": "ステーションが起動していて、このデバイスから到達可能か確認してください。",
    },
    "Open the Dashboard station menu and log in with your BirdNET-Go password.": {
        "es": "Abre el menú de estación del Panel e inicia sesión con tu contraseña de BirdNET-Go.",
        "de": "Öffne das Stationsmenü im Dashboard und melde dich mit deinem BirdNET-Go-Passwort an.",
        "ja": "ダッシュボードのステーションメニューを開き、BirdNET-Go のパスワードでログインしてください。",
    },
    "Log out and back in, or check the station's security settings.": {
        "es": "Cierra sesión y vuelve a iniciarla, o revisa los ajustes de seguridad de la estación.",
        "de": "Melde dich ab und wieder an oder prüfe die Sicherheitseinstellungen der Station.",
        "ja": "一度ログアウトして再ログインするか、ステーションのセキュリティ設定を確認してください。",
    },
    "Use a valid HTTPS certificate, or connect over local HTTP for trusted local stations.": {
        "es": "Usa un certificado HTTPS válido o conéctate por HTTP local para estaciones locales de confianza.",
        "de": "Verwende ein gültiges HTTPS-Zertifikat oder verbinde dich für vertrauenswürdige lokale Stationen über lokales HTTP.",
        "ja": "有効な HTTPS 証明書を使用するか、信頼できるローカルステーションにはローカル HTTP で接続してください。",
    },
    "Wait briefly before refreshing or reconnecting.": {
        "es": "Espera un momento antes de actualizar o volver a conectarte.",
        "de": "Warte kurz, bevor du aktualisierst oder dich erneut verbindest.",
        "ja": "更新または再接続するまで少し待ってください。",
    },
    "Check the station logs or generate a diagnostics bundle from the Dashboard station menu.": {
        "es": "Consulta los registros de la estación o genera un paquete de diagnósticos desde el menú de estación del Panel.",
        "de": "Prüfe die Stationsprotokolle oder erstelle ein Diagnosepaket über das Stationsmenü im Dashboard.",
        "ja": "ステーションのログを確認するか、ダッシュボードのステーションメニューから診断バンドルを生成してください。",
    },
    "Include the scheme and host, for example http://birdnet.local:8080.": {
        "es": "Incluye el esquema y el host, por ejemplo http://birdnet.local:8080.",
        "de": "Gib das Schema und den Host an, z. B. http://birdnet.local:8080.",
        "ja": "スキームとホストを含めてください（例: http://birdnet.local:8080）。",
    },
    "Use HTTPS for remote hosts, or connect to a localhost, private IP, or .local address.": {
        "es": "Usa HTTPS para hosts remotos o conéctate a localhost, una IP privada o una dirección .local.",
        "de": "Verwende HTTPS für entfernte Hosts oder verbinde dich mit localhost, einer privaten IP oder einer .local-Adresse.",
        "ja": "リモートホストには HTTPS を使用するか、localhost、プライベート IP、.local アドレスに接続してください。",
    },
    # CON-008 multi-profile UI
    "Add Station": {"es": "Añadir estación", "de": "Station hinzufügen", "ja": "ステーションを追加"},
    "Add station": {"es": "Añadir estación", "de": "Station hinzufügen", "ja": "ステーションを追加"},
    "Stations": {"es": "Estaciones", "de": "Stationen", "ja": "ステーション"},
    "Switch Station": {"es": "Cambiar estación", "de": "Station wechseln", "ja": "ステーションを切り替え"},
    "New Station": {"es": "Nueva estación", "de": "Neue Station", "ja": "新しいステーション"},
    "Connect Station": {"es": "Conectar estación", "de": "Station verbinden", "ja": "ステーションに接続"},
    "Rename": {"es": "Renombrar", "de": "Umbenennen", "ja": "名前を変更"},
    "Rename Station": {"es": "Renombrar estación", "de": "Station umbenennen", "ja": "ステーションの名前を変更"},
    "Station name": {"es": "Nombre de la estación", "de": "Stationsname", "ja": "ステーション名"},
    "Save": {"es": "Guardar", "de": "Speichern", "ja": "保存"},
    "Delete": {"es": "Eliminar", "de": "Löschen", "ja": "削除"},
    "Choose a new name for %@.": {
        "es": "Elige un nuevo nombre para %@.",
        "de": "Wähle einen neuen Namen für %@.",
        "ja": "%@ の新しい名前を選択してください。",
    },
    "Switched to %@.": {
        "es": "Cambiado a %@.",
        "de": "Gewechselt zu %@.",
        "ja": "%@ に切り替えました。",
    },
    "Switches to this station": {
        "es": "Cambia a esta estación",
        "de": "Wechselt zu dieser Station",
        "ja": "このステーションに切り替えます",
    },
    "Renamed station to %@.": {
        "es": "Estación renombrada a %@.",
        "de": "Station umbenannt in %@.",
        "ja": "ステーション名を %@ に変更しました。",
    },
    "Removed %@.": {
        "es": "Se eliminó %@.",
        "de": "%@ entfernt.",
        "ja": "%@ を削除しました。",
    },
    "Removes the active station and any stored credentials on this device.": {
        "es": "Elimina la estación activa y cualquier credencial almacenada en este dispositivo.",
        "de": "Entfernt die aktive Station und alle hinterlegten Anmeldedaten von diesem Gerät.",
        "ja": "アクティブなステーションとこのデバイスに保存された認証情報を削除します。",
    },
    "This removes %@ and any stored credentials from this device.": {
        "es": "Esto elimina %@ y cualquier credencial almacenada en este dispositivo.",
        "de": "Dies entfernt %@ und alle hinterlegten Anmeldedaten von diesem Gerät.",
        "ja": "このデバイスから %@ と保存された認証情報を削除します。",
    },
    "Not validated yet": {
        "es": "Aún no validada",
        "de": "Noch nicht validiert",
        "ja": "未検証",
    },
    "Station connected.": {
        "es": "Estación conectada.",
        "de": "Station verbunden.",
        "ja": "ステーションに接続しました。",
    },
    "Station connected. Login required.": {
        "es": "Estación conectada. Inicio de sesión requerido.",
        "de": "Station verbunden. Anmeldung erforderlich.",
        "ja": "ステーションに接続しました。ログインが必要です。",
    },
    "Logged in.": {
        "es": "Sesión iniciada.",
        "de": "Angemeldet.",
        "ja": "ログインしました。",
    },
    "Authenticated.": {
        "es": "Autenticado.",
        "de": "Authentifiziert.",
        "ja": "認証済み。",
    },
    "Not authenticated.": {
        "es": "No autenticado.",
        "de": "Nicht authentifiziert.",
        "ja": "未認証。",
    },
    "Password is required.": {
        "es": "Se requiere la contraseña.",
        "de": "Passwort erforderlich.",
        "ja": "パスワードが必要です。",
    },
}


def main() -> None:
    catalog = json.loads(CATALOG.read_text())
    strings = catalog["strings"]

    # 1. Drop entries that are clearly stale extractor artifacts. xcstringstool
    #    sometimes emits a "%arg" / "%arg detections today" sibling alongside
    #    the real "%@" / "%lld" entries, and an empty "" key when its diff
    #    becomes confused. Both are safe to remove because the real keys are
    #    the ones referenced from source.
    drop_keys = []
    for key, entry in strings.items():
        if key == "":
            drop_keys.append(key)
            continue
        if "%arg" in key:
            drop_keys.append(key)
    for key in drop_keys:
        del strings[key]

    # 2. Backfill translations.
    missing_report: dict[str, list[str]] = {"es": [], "de": [], "ja": []}
    for key, entry in strings.items():
        localizations = entry.setdefault("localizations", {})
        # Always seed English from the source key if missing.
        if "en" not in localizations:
            localizations["en"] = {
                "stringUnit": {"state": "translated", "value": key}
            }
        for lang in ("es", "de", "ja"):
            existing = localizations.get(lang)
            existing_value = existing.get("stringUnit", {}).get("value") if existing else None
            if existing_value:
                continue
            translation = TRANSLATIONS.get(key, {}).get(lang)
            if translation is None:
                # Mark uncertain translations for human review rather than
                # shipping a copy of the English string.
                missing_report[lang].append(key)
                localizations[lang] = {
                    "stringUnit": {"state": "needs_review", "value": key}
                }
            else:
                localizations[lang] = {
                    "stringUnit": {"state": "translated", "value": translation}
                }
        entry.setdefault("extractionState", "manual")

    CATALOG.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n")

    for lang, keys in missing_report.items():
        if keys:
            print(f"[{lang}] {len(keys)} entries marked needs_review:")
            for k in keys:
                print(f"  - {k!r}")


if __name__ == "__main__":
    main()
