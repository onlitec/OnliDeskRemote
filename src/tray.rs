use crate::client::translate;
#[cfg(windows)]
use crate::ipc::Data;
#[cfg(windows)]
use hbb_common::tokio;
use hbb_common::{allow_err, log};
use std::sync::{Arc, Mutex};
#[cfg(windows)]
use std::time::Duration;

#[cfg(windows)]
fn watch_config_path() -> &'static std::path::Path {
    std::path::Path::new(r"C:\ProgramData\OnliDeskWhatch\watch_config.json")
}

/// Lê o hash da senha de admin armazenado em watch_config.json.
#[cfg(windows)]
fn watch_admin_password_hash() -> String {
    let path = watch_config_path();
    if let Ok(content) = std::fs::read_to_string(path) {
        if let Ok(val) = serde_json::from_str::<serde_json::Value>(&content) {
            if let Some(h) = val.get("admin_password_hash").and_then(|v| v.as_str()) {
                return h.to_string();
            }
        }
    }
    String::new()
}

/// Verifica a senha contra o hash sha256$salt$hash armazenado.
/// Se stored_hash for vazio (config inicial recém criada pelo instalador), aceita "admin123".
#[cfg(windows)]
fn verify_watch_admin_password(password: &str, stored: &str) -> bool {
    if stored.is_empty() {
        // Primeiro acesso (hash ainda não configurado): aceita a senha inicial padrão "admin123"
        return password == "admin123";
    }
    let parts: Vec<&str> = stored.split('$').collect();
    if parts.len() == 3 && parts[0] == "sha256" {
        // decode hex salt
        let salt_hex = parts[1];
        let bytes: Vec<u8> = salt_hex.as_bytes().chunks(2).filter_map(|c| {
            let hi = (c[0] as char).to_digit(16)? as u8;
            let lo = (c[1] as char).to_digit(16)? as u8;
            Some((hi << 4) | lo)
        }).collect();

        use sha2::{Digest, Sha256};
        let mut hasher = Sha256::new();
        hasher.update(&bytes);
        hasher.update(password.as_bytes());
        let digest = hasher.finalize();
        // encode digest as hex and compare
        let digest_hex: String = digest.iter().map(|b| format!("{:02x}", b)).collect();
        return digest_hex == parts[2];
    }
    // compatibilidade: senha em texto plano
    stored == password
}

/// Exibe um diálogo Win32 nativo pedindo a senha do administrador.
/// Retorna `Some(senha)` se o usuário confirmou, `None` se cancelou.
#[cfg(windows)]
fn prompt_admin_password(title: &str, message: &str) -> Option<String> {
    use std::ffi::OsStr;
    use std::iter::once;
    use std::os::windows::ffi::OsStrExt;
    use winapi::ctypes::c_void;
    use winapi::um::wincred::{
        CredFree, CredUIPromptForWindowsCredentialsW, CredUnPackAuthenticationBufferW,
        CREDUI_INFOW, CREDUIWIN_GENERIC, CREDUI_MAX_PASSWORD_LENGTH,
    };
    use winapi::shared::minwindef::DWORD;

    let to_wide = |s: &str| -> Vec<u16> { OsStr::new(s).encode_wide().chain(once(0)).collect() };

    let w_title   = to_wide(title);
    let w_message = to_wide(message);

    let ui_info = CREDUI_INFOW {
        cbSize: std::mem::size_of::<CREDUI_INFOW>() as DWORD,
        hwndParent: std::ptr::null_mut(),
        pszMessageText: w_message.as_ptr(),
        pszCaptionText: w_title.as_ptr(),
        hbmBanner: std::ptr::null_mut(),
    };

    let mut auth_pkg: DWORD = 0;
    let mut out_buf: *mut c_void = std::ptr::null_mut();
    let mut out_size: DWORD = 0;
    let mut save: winapi::shared::minwindef::BOOL = 0;

    let ret = unsafe {
        CredUIPromptForWindowsCredentialsW(
            &ui_info as *const _ as *mut _,
            0,
            &mut auth_pkg,
            std::ptr::null(),
            0,
            &mut out_buf as *mut *mut c_void,
            &mut out_size,
            &mut save,
            // Genérico: caixa simples de usuário/senha, sem listar contas do
            // Windows (CREDUIWIN_ENUMERATE_ADMINS fazia o Windows mostrar o
            // seletor de contas de administrador do SISTEMA, o que parecia
            // pedir login do Windows em vez da senha do próprio app).
            CREDUIWIN_GENERIC,
        )
    };

    if ret != 0 || out_buf.is_null() {
        return None; // usuário cancelou
    }

    // Extrai a senha do buffer retornado pela CredUI
    let mut user_buf   = vec![0u16; 256];
    let mut domain_buf = vec![0u16; 256];
    let mut pass_buf   = vec![0u16; CREDUI_MAX_PASSWORD_LENGTH as usize];
    let mut user_len   = user_buf.len() as DWORD;
    let mut domain_len = domain_buf.len() as DWORD;
    let mut pass_len   = pass_buf.len() as DWORD;

    let unpacked = unsafe {
        CredUnPackAuthenticationBufferW(
            0,
            out_buf as *mut c_void,
            out_size,
            user_buf.as_mut_ptr(),
            &mut user_len,
            domain_buf.as_mut_ptr(),
            &mut domain_len,
            pass_buf.as_mut_ptr(),
            &mut pass_len,
        )
    };

    // Libera o buffer de saída
    unsafe { CredFree(out_buf as *mut c_void) };

    if unpacked == 0 {
        return None;
    }

    // pass_len já conta o nulo terminal — ajusta para não incluí-lo
    let len = if pass_len > 0 { pass_len as usize - 1 } else { 0 };
    Some(String::from_utf16_lossy(&pass_buf[..len]))
}

/// Verifica autenticação de admin e retorna true se autorizado a parar o serviço.
/// Usa CredUI em Windows; em outros SO retorna true sem pedir senha.
#[cfg(windows)]
fn authorize_stop_service() -> bool {
    // Se não for instalação com OnliDeskWhatch (config não existe), permite fechar sem senha
    if !watch_config_path().exists() {
        return true;
    }

    let stored_hash = watch_admin_password_hash();

    let password = match prompt_admin_password(
        "OnliDesk — Senha do Administrador (painel OnliDeskWhatch)",
        "Esta NÃO é a senha da sua conta do Windows.\nDigite a senha de administrador do painel OnliDeskWhatch para parar o serviço de monitoramento. Usuário: deixe em branco.",
    ) {
        Some(p) => p,
        None => {
            log::info!("Tray: stop-service cancelado pelo usuário.");
            return false;
        }
    };

    if verify_watch_admin_password(&password, &stored_hash) {
        log::info!("Tray: stop-service autorizado pelo administrador.");
        true
    } else {
        log::warn!("Tray: stop-service negado — senha incorreta.");
        // Mostra mensagem de erro
        use std::ffi::OsStr;
        use std::iter::once;
        use std::os::windows::ffi::OsStrExt;
        let msg: Vec<u16> = OsStr::new("Senha incorreta. O serviço não foi parado.").encode_wide().chain(once(0)).collect();
        let title: Vec<u16> = OsStr::new("OnliDesk — Acesso negado").encode_wide().chain(once(0)).collect();
        unsafe {
            winapi::um::winuser::MessageBoxW(
                std::ptr::null_mut(),
                msg.as_ptr(),
                title.as_ptr(),
                winapi::um::winuser::MB_ICONERROR | winapi::um::winuser::MB_OK,
            );
        }
        false
    }
}

pub fn start_tray() {
    if crate::ui_interface::get_builtin_option(hbb_common::config::keys::OPTION_HIDE_TRAY) == "Y" {
        #[cfg(not(target_os = "macos"))]
        {
            return;
        }
    }

    #[cfg(target_os = "linux")]
    crate::server::check_zombie();

    allow_err!(make_tray());
}

fn make_tray() -> hbb_common::ResultType<()> {
    // https://github.com/tauri-apps/tray-icon/blob/dev/examples/tao.rs
    use hbb_common::anyhow::Context;
    use tao::event_loop::{ControlFlow, EventLoopBuilder};
    use tray_icon::{
        menu::{Menu, MenuEvent, MenuItem},
        TrayIcon, TrayIconBuilder, TrayIconEvent as TrayEvent,
    };
    let icon: Vec<u8>;
    #[cfg(target_os = "macos")]
    {
        icon = include_bytes!("../res/mac-tray-dark-x2.png").to_vec(); // template, color não importa
    }
    #[cfg(not(target_os = "macos"))]
    {
        // PNG embutido (decodificador sempre disponível). O `.ico` embutido dava
        // erro de decode em runtime em algumas builds -> `make_tray` falhava e o
        // ícone não aparecia. Carregamento robusto: asset -> PNG -> fallback.
        icon = include_bytes!("../res/tray-icon.png").to_vec();
    }

    let (icon_rgba, icon_width, icon_height) = {
        let loaded = load_icon_from_asset().or_else(|| image::load_from_memory(&icon).ok());
        match loaded {
            Some(im) => {
                let rgba = im.into_rgba8();
                let (w, h) = rgba.dimensions();
                (rgba.into_raw(), w, h)
            }
            None => {
                log::error!("Tray: falha ao decodificar o ícone; usando fallback sólido.");
                (vec![120u8; 32 * 32 * 4], 32u32, 32u32)
            }
        }
    };
    let icon = match tray_icon::Icon::from_rgba(icon_rgba, icon_width, icon_height) {
        Ok(i) => i,
        Err(e) => {
            log::error!("Tray: from_rgba falhou ({e}); usando ícone de fallback.");
            tray_icon::Icon::from_rgba(vec![120u8; 32 * 32 * 4], 32, 32).context("tray fallback icon")?
        }
    };

    let mut event_loop = EventLoopBuilder::new().build();

    let tray_menu = Menu::new();
    let hide_stop_service = crate::ui_interface::get_builtin_option(
        hbb_common::config::keys::OPTION_HIDE_STOP_SERVICE,
    ) == "Y";
    // The tray icon is only shown when the service is running, so we don't need to check
    // the `stop-service` option here.
    let quit_i = if !hide_stop_service {
        Some(MenuItem::new(translate("Stop service".to_owned()), true, None))
    } else {
        None
    };
    let open_i = MenuItem::new(translate("Open".to_owned()), true, None);
    if let Some(quit_i) = &quit_i {
        tray_menu.append_items(&[&open_i, quit_i]).ok();
    } else {
        tray_menu.append_items(&[&open_i]).ok();
    }
    let tooltip = |count: usize| {
        if count == 0 {
            format!(
                "{} {}",
                crate::get_app_name(),
                translate("Service is running".to_owned()),
            )
        } else {
            format!(
                "{} - {}\n{}",
                crate::get_app_name(),
                translate("Ready".to_owned()),
                translate("{".to_string() + &format!("{count}") + "} sessions"),
            )
        }
    };
    let mut _tray_icon: Arc<Mutex<Option<TrayIcon>>> = Default::default();

    let menu_channel = MenuEvent::receiver();
    let tray_channel = TrayEvent::receiver();
    #[cfg(windows)]
    let (ipc_sender, ipc_receiver) = std::sync::mpsc::channel::<Data>();

    let open_func = move || {
        if cfg!(not(feature = "flutter")) {
            crate::run_me::<&str>(vec![]).ok();
            return;
        }
        #[cfg(target_os = "macos")]
        crate::platform::macos::handle_application_should_open_untitled_file();
        #[cfg(target_os = "windows")]
        {
            // Do not use "start uni link" way, it may not work on some Windows, and pop out error
            // dialog, I found on one user's desktop, but no idea why, Windows is shit.
            // Use `run_me` instead.
            // `allow_multiple_instances` in `flutter/windows/runner/main.cpp` allows only one instance without args.
            crate::run_me::<&str>(vec![]).ok();
        }
        #[cfg(target_os = "linux")]
        {
            // Do not use "xdg-open", it won't read the config.
            if crate::dbus::invoke_new_connection(crate::get_uri_prefix()).is_err() {
                if let Ok(task) = crate::run_me::<&str>(vec![]) {
                    crate::server::CHILD_PROCESS.lock().unwrap().push(task);
                }
            }
        }
    };

    #[cfg(windows)]
    std::thread::spawn(move || {
        start_query_session_count(ipc_sender.clone());
    });
    #[cfg(windows)]
    let mut last_click = std::time::Instant::now();
    #[cfg(target_os = "macos")]
    {
        use tao::platform::macos::EventLoopExtMacOS;
        event_loop.set_activation_policy(tao::platform::macos::ActivationPolicy::Accessory);
    }
    event_loop.run(move |event, _, control_flow| {
        *control_flow = ControlFlow::WaitUntil(
            std::time::Instant::now() + std::time::Duration::from_millis(100),
        );

        if let tao::event::Event::NewEvents(tao::event::StartCause::Init) = event {
            // for fixing https://github.com/onlidesk/onlidesk/discussions/10210#discussioncomment-14600745
            // so we start tray, but not to show it
            if crate::ui_interface::get_builtin_option(hbb_common::config::keys::OPTION_HIDE_TRAY) == "Y" {
                return;
            }
            // We create the icon once the event loop is actually running
            // to prevent issues like https://github.com/tauri-apps/tray-icon/issues/90
            let tray = TrayIconBuilder::new()
                .with_menu(Box::new(tray_menu.clone()))
                .with_tooltip(tooltip(0))
                .with_icon(icon.clone())
                .with_icon_as_template(true) // mac only
                .build();
            match tray {
                Ok(tray) => _tray_icon = Arc::new(Mutex::new(Some(tray))),
                Err(err) => {
                    log::error!("Failed to create tray icon: {}", err);
                }
            };

            // We have to request a redraw here to have the icon actually show up.
            // Tao only exposes a redraw method on the Window so we use core-foundation directly.
            #[cfg(target_os = "macos")]
            unsafe {
                use core_foundation::runloop::{CFRunLoopGetMain, CFRunLoopWakeUp};

                let rl = CFRunLoopGetMain();
                CFRunLoopWakeUp(rl);
            }
        }

        if let Ok(event) = menu_channel.try_recv() {
            if let Some(quit_i) = &quit_i {
                if event.id == quit_i.id() {
                    // Protegido por senha de admin do OnliDeskWhatch
                    #[cfg(windows)]
                    {
                        if !authorize_stop_service() {
                            // senha errada ou cancelado — não faz nada
                        } else if !crate::platform::uninstall_service(false, false) {
                            *control_flow = ControlFlow::Exit;
                        }
                    }
                    #[cfg(not(windows))]
                    {
                        if !crate::platform::uninstall_service(false, false) {
                            *control_flow = ControlFlow::Exit;
                        }
                    }
                } else if event.id == open_i.id() {
                    open_func();
                }
            } else if event.id == open_i.id() {
                open_func();
            }
        }

        if let Ok(_event) = tray_channel.try_recv() {
            #[cfg(target_os = "windows")]
            match _event {
                TrayEvent::Click {
                    button,
                    button_state,
                    ..
                } => {
                    if button == tray_icon::MouseButton::Left
                        && button_state == tray_icon::MouseButtonState::Up
                    {
                        if last_click.elapsed() < std::time::Duration::from_secs(1) {
                            return;
                        }
                        open_func();
                        last_click = std::time::Instant::now();
                    }
                }
                _ => {}
            }
        }

        #[cfg(windows)]
        if let Ok(data) = ipc_receiver.try_recv() {
            match data {
                Data::ControlledSessionCount(count) => {
                    _tray_icon
                        .lock()
                        .unwrap()
                        .as_mut()
                        .map(|t| t.set_tooltip(Some(tooltip(count))));
                }
                _ => {}
            }
        }
    });
}

#[cfg(windows)]
#[tokio::main(flavor = "current_thread")]
async fn start_query_session_count(sender: std::sync::mpsc::Sender<Data>) {
    let mut last_count = 0;
    loop {
        if let Ok(mut c) = crate::ipc::connect(1000, "").await {
            let mut timer = crate::rustdesk_interval(tokio::time::interval(Duration::from_secs(1)));
            loop {
                tokio::select! {
                    res = c.next() => {
                        match res {
                            Err(err) => {
                                log::error!("ipc connection closed: {}", err);
                                break;
                            }

                            Ok(Some(Data::ControlledSessionCount(count))) => {
                                if count != last_count {
                                    last_count = count;
                                    sender.send(Data::ControlledSessionCount(count)).ok();
                                }
                            }
                            _ => {}
                        }
                    }

                    _ = timer.tick() => {
                        c.send(&Data::ControlledSessionCount(0)).await.ok();
                    }
                }
            }
        }
        hbb_common::sleep(1.).await;
    }
}

fn load_icon_from_asset() -> Option<image::DynamicImage> {
    let Some(path) = std::env::current_exe().map_or(None, |x| x.parent().map(|x| x.to_path_buf()))
    else {
        return None;
    };
    #[cfg(target_os = "macos")]
    let path = path.join("../Frameworks/App.framework/Resources/flutter_assets/assets/icon.png");
    #[cfg(windows)]
    let path = path.join(r"data\flutter_assets\assets\icon.png");
    #[cfg(target_os = "linux")]
    let path = path.join(r"data/flutter_assets/assets/icon.png");
    if path.exists() {
        if let Ok(image) = image::open(path) {
            return Some(image);
        }
    }
    None
}
