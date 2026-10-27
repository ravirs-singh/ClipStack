# Homebrew cask. After the first release: `brew install --cask halvent/clipstack/clipstack`
# (host this file in a tap repo named `homebrew-clipstack`, or submit to homebrew/cask once there are enough stars).
cask "clipstack" do
  version "1.0.0"
  sha256 "REPLACE_WITH_SHASUM_FROM_release.sh"

  url "https://github.com/halvent/clipstack/releases/download/v#{version}/ClipStack-#{version}.dmg"
  name "ClipStack"
  desc "Clipboard history, screenshots with OCR, and a Dynamic-Island-style notch for macOS"
  homepage "https://github.com/halvent/clipstack"

  depends_on macos: ">= :ventura"

  app "ClipStack.app"

  zap trash: [
    "~/Library/Application Support/ClipStack",
    "~/Library/Preferences/com.halvent.clipstack.plist",
  ]
end
