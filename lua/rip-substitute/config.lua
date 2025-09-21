local M = {}
--------------------------------------------------------------------------------

local fallbackBorder = "rounded"

---@return string
local function getBorder()
	local hasWinborder, winborder = pcall(function() return vim.o.winborder end)
	if not hasWinborder or winborder == "" or winborder == "none" then return fallbackBorder end
	return winborder
end

--------------------------------------------------------------------------------

---@class RipSubstitute.Config
local defaultConfig = {
	popupWin = {
		title = " rip-substitute",
		border = getBorder(), -- `vim.o.winborder` on nvim 0.11, otherwise "rounded"
		matchCountHlGroup = "Keyword",
		noMatchHlGroup = "ErrorMsg",
		position = "bottom", ---@type "top"|"bottom"
		layoutStyle = "default", ---@type "default"|"jetbrains"
		jetbrainsFullWidth = true, -- Use full editor width for jetbrains style, else current window width
		hideSearchReplaceLabels = false,
		hideKeymapHints = false,
		disableCompletions = true, -- disables all blink.cmp completions
	},
	prefill = {
		normal = "cursorWord", ---@type "cursorWord"|false
		visual = "selection", ---@type "selection"|false (does not work with ex-command – see README)
		startInReplaceLineIfPrefill = false,
		alsoPrefillReplaceLine = false,
	},
	keymaps = {
		n = {
			abort = "q",
			confirm = "<CR>",
			prevSubstitutionInHistory = "<Up>",
			nextSubstitutionInHistory = "<Down>",
			toggleFixedStrings = "<C-f>", -- ripgrep's `--fixed-strings`
			toggleIgnoreCase = "<C-c>", -- ripgrep's `--ignore-case`
			openAtRegex101 = "R",
			showHelp = "?",
		},
		i = {
			confirm = "<C-CR>",
		},
	},
	incrementalPreview = {
		matchHlGroup = "IncSearch",
		rangeBackdrop = {
			enabled = true,
			blend = 50, -- between 0 and 100
		},
	},
	regexOptions = {
		startWithFixedStringsOn = false,
		startWithIgnoreCase = false,
		pcre2 = true, -- enables lookarounds and backreferences, but slightly slower
		autoBraceSimpleCaptureGroups = true, -- disable if using named capture groups (see README for details)
	},
	editingBehavior = {
		-- Typing `()` in the `search` line, automatically adds `$n` to the `replace` line.
		autoCaptureGroups = false,
	},
	notification = {
		onSuccess = true,
		icon = "",
	},
	debug = false, -- extra notifications for debugging
}

--------------------------------------------------------------------------------

M.config = defaultConfig

function M.setup(userConfig)
	M.config = vim.tbl_deep_extend("force", M.config, userConfig or {})
	local notify = require("rip-substitute.utils").notify

	-- MIGRATE old keymap structure
	local keymaps = M.config.keymaps
	local old_keys_found = false
	local keys_to_migrate = {}

	-- Collect top-level keys that are not n, i, or v
	for key, _ in pairs(keymaps) do
		if key ~= "n" and key ~= "i" and key ~= "v" then
			table.insert(keys_to_migrate, key)
		end
	end

	if #keys_to_migrate > 0 then
		old_keys_found = true
		for _, key in ipairs(keys_to_migrate) do
			local value = keymaps[key]
			if key == "insertModeConfirm" then
				keymaps.i.confirm = value
			else
				keymaps.n[key] = value
			end
			keymaps[key] = nil
		end
	end

	if old_keys_found then
		notify("`keymaps` configuration has changed. Please update your config to use `n` and `i` subtables for modes.", "warn")
	end

	-- set initial state for regex options
	if M.config.regexOptions.startWithFixedStringsOn then
		require("rip-substitute.state").state.useFixedStrings = true
	end
	if M.config.regexOptions.startWithIgnoreCase then
		require("rip-substitute.state").state.useIgnoreCase = true
	end

	-- DEPRECATION (2024-11-20)
	if M.config.notificationOnSuccess then ---@diagnostic disable-line: undefined-field
		local msg =
			"`notificationOnSuccess` has been deprecated. Use `notification.onSuccess` instead."
		notify(msg, "warn")
	end

	-- VALIDATE layoutStyle
	local layout = M.config.popupWin.layoutStyle
	if layout ~= "default" and layout ~= "jetbrains" then
		notify(('Invalid layoutStyle %q. Must be "default" or "jetbrains". Falling back to "default".'):format(layout), "warn")
		M.config.popupWin.layoutStyle = "default"
	end

	-- VALIDATE jetbrainsFullWidth
	if type(M.config.popupWin.jetbrainsFullWidth) ~= "boolean" then
		notify('Invalid jetbrainsFullWidth type. Must be boolean. Falling back to "true".', "warn")
		M.config.popupWin.jetbrainsFullWidth = true
	end

	-- VALIDATE `rg` installations not built with `pcre2`, see #3
	if M.config.regexOptions.pcre2 then
		vim.system({ "rg", "--pcre2-version" }, {}, function(out)
			if out.code ~= 0 or out.stderr:find("PCRE2 is not available in this build of ripgrep") then
				local msg = "`regexOptions.pcre2` has been disabled, as the installed version of `ripgrep` lacks `pcre2` support.\n\n"
					.. "Please install `ripgrep` with `pcre2` support, or disable `regexOptions.pcre2`."
				notify(msg, "warn")
				M.config.regexOptions.pcre2 = false
			end
		end)
	end

	-- VALIDATE border `none` does not work with and title/footer used by this plugin
	if M.config.popupWin.border == "none" or M.config.popupWin.border == "" then
		M.config.popupWin.border = fallbackBorder
		local msg = ('Border "none" is not supported, falling back to %q.'):format(fallbackBorder)
		notify(msg, "warn")
	end
end

--------------------------------------------------------------------------------
return M
