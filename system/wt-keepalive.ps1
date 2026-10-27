# Mantem o Windows Terminal sempre vivo: se fechar, reabre-o logo e esconde-o na area de notificacao.
# Corre escondido no inicio de sessao (tarefa TerminalKeepAlive, elevada).
# Store (laptop) ou versão portátil em ~\.local\terminal (desktop, Windows 10)
$wt = @("$env:LOCALAPPDATA\Microsoft\WindowsApps\wt.exe", "$HOME\.local\terminal\wt.exe") | Where-Object { Test-Path $_ } | Select-Object -First 1
$keys = New-Object -ComObject WScript.Shell
# home limpa: volta a esconder o que os programas foram criando (ver home-tidy.ps1)
& "$HOME\.config\home-tidy.ps1"
# SuperTerminal (WezTerm) instalado neste PC: arranca o agente dele (Ctrl+Alt+T), elevado como esta tarefa, para conseguir
# mostrar / esconder qualquer janela do WezTerm; o WezTerm que ele abre herda o admin (Kev quer o terminal sempre elevado). O Windows Terminal
# ja nao e aberto aqui (senao ficava com o Ctrl+Alt+T).
$agent = "$HOME\.local\superterminal\agent.exe"
# versao nova deixada enquanto o agente corria (o .exe em uso nao pode ser substituido): troca-se aqui, antes de arrancar
if (Test-Path "$agent.new") { Move-Item "$agent.new" $agent -Force -ErrorAction SilentlyContinue }
# WezTerm novo deixado em ~\.local\wezterm.new (o que esta em uso nao pode ser substituido): troca antes de o abrir
$wzNew = "$HOME\.local\wezterm.new"
if ((Test-Path "$wzNew\wezterm-gui.exe") -and -not (Get-Process wezterm-gui -ErrorAction SilentlyContinue)) {
    Remove-Item "$HOME\.local\wezterm.old" -Recurse -Force -ErrorAction SilentlyContinue
    Rename-Item "$HOME\.local\wezterm" 'wezterm.old' -ErrorAction SilentlyContinue; Rename-Item $wzNew 'wezterm'
}
if (Test-Path $agent) { Start-Process $agent -ArgumentList '--prelaunch'; return }

while ($true) {
    $p = Get-Process WindowsTerminal -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $p) {
        Start-Process $wt -ArgumentList '-d', $HOME
        for ($i = 0; $i -lt 100 -and -not ($p = Get-Process WindowsTerminal -ErrorAction SilentlyContinue | Where-Object MainWindowHandle -ne 0 | Select-Object -First 1); $i++) {
            Start-Sleep -Milliseconds 100
        }
        # deixa o perfil desenhar o fastfetch e esconde pelo atalho global do proprio terminal
        # (minimizar a forca apaga o conteudo do ecra)
        if ($p) { Start-Sleep -Milliseconds 1500; $keys.SendKeys('^%t') }
    }
    if ($p) { $p.WaitForExit() } else { Start-Sleep -Seconds 2 }   # sem polling: acorda so quando o terminal fecha
}
