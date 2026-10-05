// --------------------------------------------------
// LocalWhisper Frontend Controller
// Handles AJAX communication, status polling, and UI interactions
// --------------------------------------------------

document.addEventListener("DOMContentLoaded", () => {
    // Current View Navigation
    const navItems = document.querySelectorAll(".sidebar-nav li");
    const views = document.querySelectorAll(".content-view");
    
    navItems.forEach(item => {
        item.addEventListener("click", () => {
            const targetView = item.getAttribute("data-view");
            
            // Toggle navigation active class
            navItems.forEach(nav => nav.classList.remove("active"));
            item.classList.add("active");
            
            // Toggle view visibility
            views.forEach(view => {
                if (view.id === targetView) {
                    view.classList.add("active");
                } else {
                    view.classList.remove("active");
                }
            });
        });
    });

    // Global App State
    let isRecording = false;
    let pollInterval = null;
    let searchTimeout = null;

    // UI Elements
    const searchInput = document.getElementById("search-input");
    const historyList = document.getElementById("history-list");
    const webRecordBtn = document.getElementById("web-record-btn");
    const liveStatusBanner = document.getElementById("live-status-banner");
    const liveStatusText = document.getElementById("live-status-text");
    
    const statusDaemonBadge = document.querySelector("#status-daemon .status-badge");
    const statusWhisperBadge = document.querySelector("#status-whisper .status-badge");
    const statusOllamaBadge = document.querySelector("#status-ollama .status-badge");
    
    const settingsForm = document.getElementById("settings-form");
    const saveSettingsBtn = document.getElementById("save-settings-btn");
    const ollamaModelSelect = document.getElementById("ollama_model");
    const ollamaEnabledCheckbox = document.getElementById("ollama_enabled");
    const ollamaModelGroup = document.getElementById("ollama-model-group");
    const ollamaPromptGroup = document.getElementById("ollama-prompt-group");
    
    const toast = document.getElementById("toast-message");

    // Initialize Page
    loadHistory();
    loadSettings();
    startStatusPolling();

    // 1. Polling System-Status
    function startStatusPolling() {
        pollStatus();
        pollInterval = setInterval(pollStatus, 1500);
    }

    async function pollStatus() {
        try {
            const response = await fetch("/api/status");
            if (!response.ok) throw new Error("Server offline");
            
            const data = await response.json();
            
            // Daemon status update
            updateDaemonUI(data.daemon_status, data.daemon_recording);
            
            // Whisper status update (is online if daemon is active or starting)
            if (data.daemon_status !== "inaktiv" && data.daemon_status !== "Fehler") {
                statusWhisperBadge.className = "status-badge online";
                statusWhisperBadge.innerHTML = `<span class="dot"></span>Aktiv`;
            } else {
                statusWhisperBadge.className = "status-badge offline";
                statusWhisperBadge.innerHTML = `<span class="dot"></span>Offline`;
            }
            
            // Ollama status update
            if (data.ollama_running) {
                statusOllamaBadge.className = "status-badge online";
                statusOllamaBadge.innerHTML = `<span class="dot"></span>Online`;
                
                // Populate Ollama models list if empty or changed
                populateOllamaModels(data.ollama_models);
            } else {
                statusOllamaBadge.className = "status-badge offline";
                statusOllamaBadge.innerHTML = `<span class="dot"></span>Offline`;
            }
            
        } catch (error) {
            console.error("Poller Error:", error);
            // System feels offline
            setSystemOffline();
        }
    }

    function updateDaemonUI(status, recording) {
        // Toggle record state based on backend state
        if (recording) {
            isRecording = true;
            webRecordBtn.classList.add("active");
            webRecordBtn.innerHTML = `<i class="fa-solid fa-stop"></i> Stoppen (Option+Space)`;
            
            // Show status banner
            liveStatusBanner.classList.remove("hidden");
            liveStatusBanner.className = "live-status-banner";
            liveStatusText.textContent = "Aufnahme läuft... Sprich jetzt.";
            
            statusDaemonBadge.className = "status-badge recording";
            statusDaemonBadge.innerHTML = `<span class="dot"></span>Aufnahme`;
        } else {
            isRecording = false;
            webRecordBtn.classList.remove("active");
            webRecordBtn.innerHTML = `<i class="fa-solid fa-microphone"></i> Diktieren (Option+Space)`;
            
            if (status === "bereit") {
                liveStatusBanner.classList.add("hidden");
                statusDaemonBadge.className = "status-badge online";
                statusDaemonBadge.innerHTML = `<span class="dot"></span>Bereit`;
            } else if (status === "transkribiert...") {
                liveStatusBanner.classList.remove("hidden");
                liveStatusBanner.className = "live-status-banner transcribing";
                liveStatusText.textContent = "Verarbeite Sprache... Bitte warten.";
                
                statusDaemonBadge.className = "status-badge processing";
                statusDaemonBadge.innerHTML = `<span class="dot"></span>Whisper`;
            } else if (status.includes("verfeinert")) {
                liveStatusBanner.classList.remove("hidden");
                liveStatusBanner.className = "live-status-banner transcribing";
                liveStatusText.textContent = "KI-Veredelung (Ollama)... Verfeinere Grammatik.";
                
                statusDaemonBadge.className = "status-badge processing";
                statusDaemonBadge.innerHTML = `<span class="dot"></span>Gemma 4`;
            } else if (status === "fügt ein...") {
                liveStatusBanner.classList.remove("hidden");
                liveStatusBanner.className = "live-status-banner transcribing";
                liveStatusText.textContent = "Füge Text am Cursor ein...";
                
                statusDaemonBadge.className = "status-badge processing";
                statusDaemonBadge.innerHTML = `<span class="dot"></span>Pasting`;
            } else {
                liveStatusBanner.classList.add("hidden");
                statusDaemonBadge.className = "status-badge offline";
                statusDaemonBadge.innerHTML = `<span class="dot"></span>Offline`;
            }
        }
    }

    function setSystemOffline() {
        statusDaemonBadge.className = "status-badge offline";
        statusDaemonBadge.innerHTML = `<span class="dot"></span>Offline`;
        statusWhisperBadge.className = "status-badge offline";
        statusWhisperBadge.innerHTML = `<span class="dot"></span>Offline`;
        statusOllamaBadge.className = "status-badge offline";
        statusOllamaBadge.innerHTML = `<span class="dot"></span>Offline`;
        liveStatusBanner.classList.add("hidden");
    }

    function populateOllamaModels(models) {
        const currentSelection = ollamaModelSelect.value;
        
        // Save existing options to check if list changed
        const existingModels = Array.from(ollamaModelSelect.options).map(opt => opt.value);
        const modelsChanged = models.length !== existingModels.length || !models.every(m => existingModels.includes(m));
        
        if (modelsChanged) {
            ollamaModelSelect.innerHTML = "";
            if (models.length === 0) {
                ollamaModelSelect.innerHTML = `<option value="">Keine Modelle gefunden</option>`;
            } else {
                models.forEach(model => {
                    const opt = document.createElement("option");
                    opt.value = model;
                    opt.textContent = model;
                    if (model === currentSelection) {
                        opt.selected = true;
                    }
                    ollamaModelSelect.appendChild(opt);
                });
            }
        }
    }

    // 2. Fetch History & Render Cards
    async function loadHistory(searchQuery = "") {
        try {
            const url = searchQuery ? `/api/history?q=${encodeURIComponent(searchQuery)}` : "/api/history";
            const response = await fetch(url);
            if (!response.ok) throw new Error("Verlauf konnte nicht geladen werden");
            
            const data = await response.json();
            renderHistory(data.history);
        } catch (error) {
            console.error("Load History Error:", error);
            historyList.innerHTML = `
                <div class="empty-state">
                    <i class="fa-solid fa-circle-exclamation" style="color: var(--accent-red)"></i>
                    <p>Fehler beim Laden des Diktierverlaufs.</p>
                </div>
            `;
        }
    }

    function renderHistory(entries) {
        if (!entries || entries.length === 0) {
            historyList.innerHTML = `
                <div class="empty-state">
                    <i class="fa-solid fa-microphone-slash"></i>
                    <p>Keine Diktate gefunden. Drücke den Shortcut und nimm dein erstes Diktat auf!</p>
                </div>
            `;
            return;
        }

        historyList.innerHTML = "";
        
        entries.forEach(entry => {
            const card = document.createElement("div");
            card.className = "dictation-card";
            card.setAttribute("data-id", entry.id);
            
            // Format timestamp (YYYY-MM-DD HH:MM:SS)
            const date = new Date(entry.timestamp);
            const formattedDate = date.toLocaleString("de-DE", {
                day: "2-digit",
                month: "2-digit",
                year: "numeric",
                hour: "2-digit",
                minute: "2-digit",
                second: "2-digit"
            });
            
            card.innerHTML = `
                <div class="card-header">
                    <div class="card-metadata">
                        <span class="app-badge"><i class="fa-solid fa-window-maximize"></i> ${entry.app || "Unbekannte App"}</span>
                        <span><i class="fa-solid fa-clock"></i> ${formattedDate}</span>
                        <span><i class="fa-solid fa-wave-square"></i> ${entry.duration ? entry.duration.toFixed(1) : 0}s</span>
                        <span><i class="fa-solid fa-hashtag"></i> ${entry.num_words || 0} Wörter</span>
                    </div>
                    
                    <div class="card-actions">
                        <button class="action-btn copy" title="Text kopieren">
                            <i class="fa-regular fa-copy"></i>
                        </button>
                        <button class="action-btn delete" title="Löschen">
                            <i class="fa-regular fa-trash-can"></i>
                        </button>
                    </div>
                </div>
                
                <div class="refined-text">${entry.refined_text || entry.raw_text}</div>
                
                ${entry.refined_text && entry.refined_text !== entry.raw_text ? `
                <div class="raw-accordion">
                    <button class="accordion-trigger">
                        <i class="fa-solid fa-chevron-down"></i> Roh-Transkription anzeigen
                    </button>
                    <div class="accordion-content">
                        ${entry.raw_text}
                    </div>
                </div>
                ` : ""}
            `;
            
            // Accordion Logic
            const accordionTrigger = card.querySelector(".accordion-trigger");
            const accordionContent = card.querySelector(".accordion-content");
            if (accordionTrigger && accordionContent) {
                accordionTrigger.addEventListener("click", () => {
                    accordionTrigger.classList.toggle("expanded");
                    accordionContent.classList.toggle("open");
                });
            }
            
            // Copy Action
            card.querySelector(".copy").addEventListener("click", () => {
                copyTextToClipboard(entry.refined_text || entry.raw_text);
            });
            
            // Delete Action
            card.querySelector(".delete").addEventListener("click", () => {
                deleteEntry(entry.id);
            });
            
            historyList.appendChild(card);
        });
    }

    // Helper: Copy to Clipboard & show Toast
    function copyTextToClipboard(text) {
        navigator.clipboard.writeText(text).then(() => {
            // Show toast message
            toast.classList.add("show");
            setTimeout(() => {
                toast.classList.remove("show");
            }, 2000);
        }).catch(err => {
            console.error("Kopieren fehlgeschlagen:", err);
        });
    }

    // Helper: Soft-delete entry
    async function deleteEntry(id) {
        if (!confirm("Möchtest Du dieses Diktat wirklich löschen?")) return;
        
        try {
            const response = await fetch(`/api/delete/${id}`, { method: "POST" });
            if (response.ok) {
                // Delete element from UI with animation
                const card = document.querySelector(`.dictation-card[data-id="${id}"]`);
                if (card) {
                    card.style.opacity = "0";
                    card.style.transform = "scale(0.95)";
                    setTimeout(() => {
                        card.remove();
                        // Reload if list is empty
                        if (historyList.children.length === 0) {
                            loadHistory();
                        }
                    }, 300);
                }
            }
        } catch (error) {
            console.error("Delete Error:", error);
        }
    }

    // 3. Search input with Debounce
    searchInput.addEventListener("input", () => {
        clearTimeout(searchTimeout);
        const query = searchInput.value.trim();
        searchTimeout = setTimeout(() => {
            loadHistory(query);
        }, 300);
    });

    // 4. Global hotkey / Toggle via Web UI
    webRecordBtn.addEventListener("click", async () => {
        try {
            webRecordBtn.disabled = true;
            const response = await fetch("/api/record/toggle", { method: "POST" });
            const data = await response.json();
            if (!data.success) {
                alert("Aufnahme konnte nicht gestartet werden. Läuft der Hintergrund-Daemon?");
            }
        } catch (error) {
            console.error("Record Toggle Error:", error);
            alert("Aufnahme konnte nicht getriggert werden. Serververbindung prüfen.");
        } finally {
            webRecordBtn.disabled = false;
        }
    });

    // 5. Load Settings
    async function loadSettings() {
        try {
            const response = await fetch("/api/settings");
            if (!response.ok) throw new Error("Settings fetch failed");
            
            const settings = await response.json();
            
            // Populate form
            document.getElementById("whisper_model").value = settings.whisper_model || "base";
            document.getElementById("whisper_language").value = settings.whisper_language || "auto";
            document.getElementById("global_hotkey").value = settings.global_hotkey || "option+space";
            
            ollamaEnabledCheckbox.checked = settings.ollama_enabled === "true";
            document.getElementById("system_prompt").value = settings.system_prompt || "";
            document.getElementById("custom_vocabulary").value = settings.custom_vocabulary || "";
            
            // Save model selection globally to re-apply after tags list is loaded by poller
            ollamaModelSelect.setAttribute("data-stored-val", settings.ollama_model || "");
            
            // Toggle Ollama fields initially
            toggleOllamaFormFields(ollamaEnabledCheckbox.checked);
            
        } catch (error) {
            console.error("Load Settings Error:", error);
        }
    }

    // Toggle Ollama inputs visible/hidden
    ollamaEnabledCheckbox.addEventListener("change", () => {
        toggleOllamaFormFields(ollamaEnabledCheckbox.checked);
    });

    function toggleOllamaFormFields(enabled) {
        if (enabled) {
            ollamaModelGroup.classList.remove("hidden");
            ollamaPromptGroup.classList.remove("hidden");
        } else {
            ollamaModelGroup.classList.add("hidden");
            ollamaPromptGroup.classList.add("hidden");
        }
    }

    // 6. Save Settings
    saveSettingsBtn.addEventListener("click", async () => {
        saveSettingsBtn.disabled = true;
        const originalText = saveSettingsBtn.innerHTML;
        saveSettingsBtn.innerHTML = `<i class="fa-solid fa-spinner fa-spin"></i> Speichere...`;
        
        const payload = {
            whisper_model: document.getElementById("whisper_model").value,
            whisper_language: document.getElementById("whisper_language").value,
            global_hotkey: document.getElementById("global_hotkey").value.trim().toLowerCase(),
            ollama_enabled: ollamaEnabledCheckbox.checked ? "true" : "false",
            ollama_model: ollamaModelSelect.value,
            system_prompt: document.getElementById("system_prompt").value,
            custom_vocabulary: document.getElementById("custom_vocabulary").value.trim()
        };
        
        try {
            const response = await fetch("/api/settings", {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: json = JSON.stringify(payload)
            });
            
            if (response.ok) {
                saveSettingsBtn.innerHTML = `<i class="fa-solid fa-circle-check"></i> Gespeichert!`;
                saveSettingsBtn.style.background = "linear-gradient(135deg, var(--accent-green), #047857)";
                
                setTimeout(() => {
                    saveSettingsBtn.innerHTML = originalText;
                    saveSettingsBtn.style.background = "";
                    saveSettingsBtn.disabled = false;
                }, 2000);
            } else {
                throw new Error("Save request rejected");
            }
        } catch (error) {
            console.error("Save Settings Error:", error);
            saveSettingsBtn.innerHTML = `<i class="fa-solid fa-circle-xmark"></i> Fehler beim Speichern`;
            saveSettingsBtn.style.background = "linear-gradient(135deg, var(--accent-red), #B91C1C)";
            
            setTimeout(() => {
                saveSettingsBtn.innerHTML = originalText;
                saveSettingsBtn.style.background = "";
                saveSettingsBtn.disabled = false;
            }, 2500);
        }
    });

    // Auto-reload history when recording completes (transition from transcribing -> bereit)
    let lastDaemonStatus = "bereit";
    setInterval(async () => {
        try {
            const response = await fetch("/api/status");
            if (response.ok) {
                const data = await response.json();
                if (data.daemon_status === "bereit" && lastDaemonStatus !== "bereit") {
                    // Just finished! Reload history to show new dictation card!
                    loadHistory(searchInput.value.trim());
                }
                lastDaemonStatus = data.daemon_status;
            }
        } catch (e) {}
    }, 1500);
});
