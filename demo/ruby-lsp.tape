# README demo for ruby-lsp.nvim
#
# Render from the repo root:
#   vhs demo/ruby-lsp.tape
#
# demo/setup.sh copies demo/sample to /tmp/ruby-lsp-demo and installs its bundle there.
# Ruby LSP itself runs from the global ruby-lsp gem, as most people install it.

Output demo.gif

Require bash
Require ruby
Require bundle
Require ruby-lsp
Require rdbg
Require nvim

Set Shell "bash"
Set FontFamily "MonoLisaCode, JetBrainsMono Nerd Font"
Set FontSize 15
Set Width 1200
Set Height 720
Set Padding 16
Set Theme "OneHalfDark"
Set TypingSpeed 70ms
Set CursorBlink false

# Setup: sandbox project, then open the test file once Ruby LSP has added its code lenses
Hide
Type "bash demo/setup.sh && source /tmp/ruby-lsp-demo/env.sh && cd /tmp/ruby-lsp-demo/calculator && nvim -u $DEMO_INIT spec/calculator_spec.rb"
Enter
Wait+Screen@240s /Run in terminal/
Sleep 1s
Show

Sleep 1.5s

# Neotest summary: specs discovered through Ruby LSP
Space
Type "ts"
Wait+Screen /averages/
Sleep 1.5s

# Run the whole describe block from its code lens. With neotest installed, Run goes through neotest.
Type "5G"
Sleep 500ms
Type "gll"
Wait+Screen /Code lenses/
Sleep 1.2s
Enter
Wait+Screen /✖/
Sleep 2.5s

# Run the failing example in a terminal (toggleterm), which stays open on failure
Type "16G"
Sleep 500ms
Type "gll"
Wait+Screen /Code lenses/
Sleep 800ms
Type "terminal"
Sleep 800ms
Enter
Wait+Screen /1 example, 1 failure/
Sleep 3.5s

# Close the terminal off camera
Hide
Ctrl+\
Ctrl+N
Ctrl+W
Type "c"
Sleep 500ms
Show

# Close the summary to make room, set a breakpoint, and debug the failing example
Space
Type "ts"
Sleep 600ms
Type "20G"
Sleep 400ms
Type ":DapToggleBreakpoint"
Sleep 600ms
Enter
Sleep 1s
Type "16G"
Sleep 400ms
Type "gll"
Wait+Screen /Code lenses/
Sleep 800ms
Type "debug"
Sleep 800ms
Enter

# dap-ui opens at the breakpoint with the local variables
Wait+Screen@30s /Local variables/
Wait+Screen /average Integer = 63/
Sleep 4.5s
