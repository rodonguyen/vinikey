.pragma library

// Panel and tooltip text, Vietnamese first. Unknown keys fall back to English,
// then to the key itself, so a missing string shows up as a key rather than blank.
var table = {
  vi: {
    languageDesc: "Tiếng Việt (tắt = English)",
    moreOptions: "Tùy chọn khác",
    fewerOptions: "Thu gọn",
    typing: "Gõ tiếng Việt",
    shortcut: "Phím tắt",
    notRunning: "fcitx5 chưa chạy",
    secTyping: "GÕ PHÍM",
    inputMethod: "Kiểu gõ",
    modern: "Đặt dấu kiểu mới",
    modernDesc: "hoà, thuý thay vì hòa, thúy",
    free: "Bỏ dấu tự do",
    freeDesc: "Đặt dấu ở cuối từ",
    restore: "Khôi phục từ tiếng Anh",
    restoreDesc: "Hoàn tác dấu ở các từ như “window”",
    spell: "Kiểm tra chính tả",
    spellDesc: "Chặn dấu ở từ không thể là tiếng Việt",
    secTools: "CÔNG CỤ",
    reload: "Khởi động lại fcitx5",
    reloadTip: "Khởi động lại bộ gõ khi gõ bị kẹt",
    fullSettings: "Cài đặt đầy đủ",
    fullSettingsTip: "Mở cửa sổ cấu hình fcitx5",
    tipVi: "Tiếng Việt (Bamboo)",
    tipEn: "Tiếng Anh",
    tipDown: "fcitx5 chưa chạy (hoặc thiếu fcitx5-remote)",
    toSwitch: "để chuyển"
  },
  en: {
    languageDesc: "English (on = Tiếng Việt)",
    moreOptions: "More options",
    fewerOptions: "Show less",
    typing: "Vietnamese typing",
    shortcut: "Shortcut",
    notRunning: "fcitx5 is not running",
    secTyping: "TYPING",
    inputMethod: "Input method",
    modern: "Modern tone placement",
    modernDesc: "hoà, thuý instead of hòa, thúy",
    free: "Free tone marking",
    freeDesc: "Put the tone mark at the end of the word",
    restore: "Restore English words",
    restoreDesc: "Undo marks on words like “window”",
    spell: "Spell check",
    spellDesc: "Block marks on words that can't be Vietnamese",
    secTools: "TOOLS",
    reload: "Reload fcitx5",
    reloadTip: "Restart the input method if typing gets stuck",
    fullSettings: "Full settings",
    fullSettingsTip: "Open the fcitx5 configuration window",
    tipVi: "Vietnamese (Bamboo)",
    tipEn: "English",
    tipDown: "fcitx5 not running (or fcitx5-remote missing)",
    toSwitch: "to switch"
  }
}

function tr(lang, key) {
  var t = table[lang] || table.vi
  if (t[key] !== undefined) return t[key]
  return table.en[key] !== undefined ? table.en[key] : key
}
