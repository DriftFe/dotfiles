-- Base2Tone Lavender Dark for Neovim
-- Faithful port of the official Kitty theme

local colors = {
  bg = "#201d2a",
  bg2 = "#2c2839",
  bg3 = "#4b455f",
  fg = "#9992b0",
  fg2 = "#b2a4bc",
  fg3 = "#faf8fc",
  comment = "#625a7c",
  purple = "#9375f5",
  purple_bright = "#dba8ff",
  violet = "#d294ff",
  magenta = "#b042ff",
  blue = "#a286fd",
  cyan = "#b5a0fe",
  selection = "#2c2839",
  border = "#4b455f",
}

local M = {}

function M.setup()
  vim.cmd("highlight clear")
  if vim.fn.exists("syntax_on") then
    vim.cmd("syntax reset")
  end
  vim.o.background = "dark"
  vim.g.colors_name = "base2tone-lavender-dark"

  local hl = vim.api.nvim_set_hl

  -- Base UI
  hl(0, "Normal", { fg = colors.fg, bg = colors.bg })
  hl(0, "NormalFloat", { fg = colors.fg, bg = colors.bg2 })
  hl(0, "FloatBorder", { fg = colors.border, bg = colors.bg2 })
  hl(0, "CursorLine", { bg = colors.bg2 })
  hl(0, "LineNr", { fg = colors.comment })
  hl(0, "CursorLineNr", { fg = colors.fg, bold = true })
  hl(0, "SignColumn", { bg = colors.bg })
  hl(0, "VertSplit", { fg = colors.border })
  hl(0, "WinSeparator", { fg = colors.border })

  -- Syntax
  hl(0, "Comment", { fg = colors.comment, italic = true })
  hl(0, "String", { fg = colors.violet })
  hl(0, "Number", { fg = colors.purple_bright })
  hl(0, "Boolean", { fg = colors.purple })
  hl(0, "Function", { fg = colors.blue })
  hl(0, "Keyword", { fg = colors.purple })
  hl(0, "Type", { fg = colors.blue })
  hl(0, "Operator", { fg = colors.cyan })
  hl(0, "PreProc", { fg = colors.cyan })

  -- Visual & Search
  hl(0, "Visual", { bg = colors.selection })
  hl(0, "Search", { bg = colors.bg3, fg = colors.fg3 })
  hl(0, "IncSearch", { bg = colors.magenta, fg = colors.bg })

  -- Treesitter
  hl(0, "@variable", { fg = colors.fg })
  hl(0, "@function", { fg = colors.blue })
  hl(0, "@keyword", { fg = colors.purple })
  hl(0, "@string", { fg = colors.violet })
  hl(0, "@type", { fg = colors.blue })
  hl(0, "@comment", { fg = colors.comment, italic = true })
end

return M
