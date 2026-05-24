# typed: false
# frozen_string_literal: true

# Windows-shaped formula for ripgrep. Points at BurntSushi's prebuilt
# Windows zip rather than a source build, so brew install does not
# need a Windows C/Rust toolchain. The formula behaves like a normal
# Homebrew formula otherwise - install method runs in an extracted
# work directory, bin.install copies the executable into the keg's
# bin, and Homebrew's link step (with windows-link-strategy.patch)
# emits .cmd + .ps1 shim pairs into <prefix>\bin.
class Ripgrep < Formula
  desc "Fast recursive grep alternative (Windows binary distribution)"
  homepage "https://github.com/BurntSushi/ripgrep"
  url "https://github.com/BurntSushi/ripgrep/releases/download/15.1.0/ripgrep-15.1.0-x86_64-pc-windows-msvc.zip"
  sha256 "124510b94b6baa3380d051fdf4650eaa80a302c876d611e9dba0b2e18d87493a"
  license "Unlicense"
  version "15.1.0"

  def install
    # The zip extracts into a top-level directory like
    # `ripgrep-15.1.0-x86_64-pc-windows-msvc/`. The contents of that
    # directory become CWD when Homebrew invokes us, so reference the
    # binary by name.
    bin.install "rg.exe"

    # Manpage + bash/PowerShell completion ship in the zip too. Keep
    # them under share/ where downstream consumers expect them.
    man1.install "doc/rg.1" if File.exist?("doc/rg.1")
    bash_completion.install "complete/rg.bash" if File.exist?("complete/rg.bash")
    fish_completion.install "complete/rg.fish" if File.exist?("complete/rg.fish")
    zsh_completion.install "complete/_rg" if File.exist?("complete/_rg")
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/rg --version")
  end
end
