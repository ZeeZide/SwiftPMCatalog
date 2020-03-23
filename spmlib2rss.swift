#!/usr/bin/swift sh

import Foundation
import Shell // @AlwaysRightInstitute

let PATH = "/Users/helge/dev/Swift/Catalogs/SwiftPMLibrary"
let FILE = "packages.json"
let debug = false
let count = 50

setenv("TZ", "GMT", 1)
FileManager.default.changeCurrentDirectoryPath(PATH)    

let dateParser : ISO8601DateFormatter = {
  let fmt = ISO8601DateFormatter()
  fmt.timeZone = TimeZone(secondsFromGMT: 0)
  return fmt
}()

// git log -- packages.json
func findCommitsThatChangedFile(_ file: String) 
     -> [ ( hash: String, date: Date, author: String ) ] 
{
  return shell.git("log", "--date=iso-strict-local", "--", file)
    .stdout
    .components(separatedBy: "\ncommit ")
    .filter { !$0.isEmpty }
    .map {
      let lines = $0.split(separator: "\n")
      let hash  = lines[0].hasPrefix("commit ")
                ? lines[0].dropFirst(7) 
                : lines[0]
      // 2020-03-20T20:22:38+00:00
      let dateString = lines.first(where: { $0.hasPrefix("Date:") } )!
                            .dropFirst(5)
                            .trimmingCharacters(in: .whitespaces)
      let author     = lines.first(where: { $0.hasPrefix("Author:") } )!
                            .dropFirst(7)
                            .trimmingCharacters(in: .whitespaces)
      let date = dateParser.date(from: dateString)!
      return ( hash: String(hash), date: date, author: author )
    }
}

func loadPackageURLsInCommit(_ hash: String) -> Set<URL> {
  let archive = shell.git("archive", hash, FILE, "| tar -x -O")
  let json    = archive.stdout.data(using: .utf8)!
  guard let urls = try? JSONDecoder().decode([ URL ].self, from: json) else {
    return [] // This DOES happen! The repo had invalid JSON early on.
  }
  return Set(urls.map { $0.deletingPathExtension() })
}


let orderedCommitHashes = findCommitsThatChangedFile(FILE) [0..<count]
var hashToSet = [ String : Set<URL> ]()

if debug {
  print("Loading:", terminator: ""); fflush(stdout)
}

for ( hash, _, _ ) in orderedCommitHashes {
  hashToSet[hash] = loadPackageURLsInCommit(hash)
  if debug {
    print(" ★", terminator: ""); fflush(stdout)
  }
}
if debug {
  print()
  print("Done: #\(hashToSet.count) sets.")
}


func calculatePackageAdditions() -> 
     [ ( hash: String, newURLs: [ URL ], date: Date, author: String ) ] 
{
  var result = [( hash: String, newURLs: [URL], date: Date, author: String )]()
  for ( idx, ( hash, date, author ) ) in orderedCommitHashes.enumerated() {
    if idx + 1 == orderedCommitHashes.endIndex { break }
    let predHash   = orderedCommitHashes[idx + 1].hash
    let predSet    = hashToSet[predHash]!
    var workingSet = hashToSet[hash]!
    workingSet.subtract(predSet)
    guard !workingSet.isEmpty else { continue }
    
    // skip unreadable sets, this is not 100 correct
    guard !predSet.isEmpty else { continue }
  
    result.append( (
      hash    : hash, 
      newURLs : workingSet.sorted { $0.absoluteString < $1.absoluteString },
      date    : date,
      author  : author
    ) ) 
  }
  return result
}

func parseAuthor(_ s: String) -> ( name: String, email: String? ) {
  guard let o = s.firstIndex(of: "<"),
        let c = s.lastIndex (of: ">"),
        let a = s.firstIndex(of: "@") else { return ( name: s, email: nil ) }
  let name  = s[..<o]
  let email = s[s.index(after: o)..<c]
  return ( name: String(name), email: email.isEmpty ? nil : String(email) )
}


// MARK: - Generate RSS

let httpFormatter : DateFormatter = {
  let df = DateFormatter()
  df.locale     = .init(identifier: "en_US_POSIX")
  df.calendar   = .init(identifier: .gregorian)
  df.timeZone   = TimeZone(secondsFromGMT: 0)
  df.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
  return df
}()

func xmlEscape(_ s: String) -> String {
  return s.replacingOccurrences(of: "\"", with: "&quot;")
          .replacingOccurrences(of: "&",  with: "&amp;")
          .replacingOccurrences(of: "'",  with: "&apos;")
          .replacingOccurrences(of: "<",  with: "&lt;")
          .replacingOccurrences(of: ">",  with: "&gt;")
}
func urlEscape(_ s: String) -> String {
   return s.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? s
}

let now          = Date()
let ttlInMinutes = 240

print(
  """
  <?xml version="1.0" encoding=\"UTF-8\"?>
  <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom" 
     	 xmlns:content="http://purl.org/rss/1.0/modules/content">
    <channel>
      <title>SwiftPM Library - New Packages</title>
      <link>https://swiftpm.co</link>
      <language>en-us</language>
      <lastBuildDate>\(httpFormatter.string(for: now)!)</lastBuildDate>
      <pubDate>\(httpFormatter.string(for: now)!)</pubDate>
      <ttl>\(ttlInMinutes)</ttl>
  """
)
defer { print("</channel>\n</rss>") }

for ( hash, newURLs, date, author ) in calculatePackageAdditions() {
  if debug {
    print("New in:", hash)
    if newURLs.count > 10 {
      print("TOO MANY NEW URLS?!", newURLs.count, author, date)
    }
    for url in newURLs.prefix(10) { // limit
      print("  ", url)
    }  
  }
  guard !newURLs.isEmpty else { continue }
  
  let ( authorName, email ) = parseAuthor(author)
  
  for url in newURLs.prefix(30) {
    let guid    = hash + "|" + url.absoluteString
    let pc      = url.deletingPathExtension().path.split(separator: "/")
    let package = pc.dropFirst().joined(separator: " / ")
    let org     = pc.first ?? "?"
    
    print("      <item>"); defer { print("      </item>") }
    print(
      """
            <guid>\(guid)</guid>
            <title>Added “\(xmlEscape(package))” @\(org)</title>
            <pubDate>\(httpFormatter.string(for: date)!)</pubDate>
            <link>\(url.absoluteString)</link>
            <description>
              \(xmlEscape(author)) was so kind to submit a new
              Swift package called 
              &quot;\(xmlEscape(package))&quot; (@\(org))
              to the SwiftPM Library.
            </description>
      """
    )
    do {
      print("      <content:encoded><![CDATA[", terminator: "")
      defer { print("]]></content:encoded>") }
      
      print(author)
      print(" was so kind to submit a new Swift package called ") 
      print("<a href='\(url.absoluteString)'><b>\(package)</b></a>")
      print(" (")
      print("<a href='https://github.com/\(urlEscape(String(org)))'>@\(org)</a>")
      print(") to the ")
      print("<a href='https://swiftpm.co/?query=\(urlEscape(package))'>SwiftPM Library</a>.")
      
      print("<br /><hr /><small>")
      
      print("<li>New Package on GitHub: <a href='\(url.absoluteString)'>\(package)</a></li>")
      print("<li>GitHub Organization: ")
      print("<a href='https://github.com/\(urlEscape(String(org)))'>@\(org)</a>")
      print("</li>")
      if let email = email, !email.isEmpty {
        print("<li>Send \(authorName) an email: <a href='mailto:\(email)'>\(email)</a>")
        print("</li>")
      }
      
      print("<li><a href='https://swiftpm.co/'>SwiftPM Library</a> ")
      print("by <a href='https://daveverwer.com'>Dave Verwer</a>")
      print("</li>")

      print("<li>")
      print("A small macOS app to browse packages:")
      print("<a href='https://zeezide.com/en/products/swiftpmcatalog/index.html'>SwiftPM Catalog</a></li>")
      print("</small>")
    }
  }
}
