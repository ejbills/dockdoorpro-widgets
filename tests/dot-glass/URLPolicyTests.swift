import Foundation
@main struct URLPolicyTests {
 static func main() {
  precondition(DotURLPolicy.conversation("https://chatgpt.com/dots/00000000-0000-0000-0000-000000000001?private=x#fragment")?.absoluteString == "https://chatgpt.com/dots/00000000-0000-0000-0000-000000000001")
  for value in ["http://chatgpt.com/dots/a", "https://chatgpt.com.evil.test/dots/a", "https://user:pass@chatgpt.com/dots/a", "file:///dots/a", "https://chatgpt.com:123/dots/a", "https://chatgpt.com/c/a", "https://chatgpt.com/dots/", "https://chatgpt.com/dots/home", "https://chatgpt.com/dots/new"] {
   precondition(DotURLPolicy.conversation(value) == nil, value)
  }
  precondition(DotURLPolicy.allowsNavigation(URL(string:"https://auth.openai.com/authorize")!))
  precondition(!DotURLPolicy.allowsNavigation(URL(string:"https://auth.openai.com.evil.test/authorize")!))
  var directory = DotDirectory()
  let first = "https://chatgpt.com/dots/00000000-0000-0000-0000-000000000001"
  let second = "https://chatgpt.com/dots/00000000-0000-0000-0000-000000000002"
  directory.remember(url: first, name: "Dotty")
  directory.remember(url: second, name: "Widget Test")
  directory.remember(url: first, name: "Your dot")
  precondition(directory.profiles.count == 2 && directory.profiles[0].name == "Dotty")
  directory.remember(url: first, name: "Renamed")
  precondition(directory.profiles.count == 2 && directory.profiles[0].name == "Renamed")
  directory.remember(url: "https://chatgpt.com/dots/home", name: "Invalid")
  precondition(directory.profiles.count == 2)
  let restored = try! JSONDecoder().decode(DotDirectory.self, from: JSONEncoder().encode(directory))
  precondition(restored.profiles == directory.profiles)
  print("URL and origin boundary checks passed")
 }
}
