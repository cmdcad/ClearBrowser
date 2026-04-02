import SwiftUI
import WebKit
import Foundation
import UIKit


class SearchManager {
    // MARK: - URL Validation & Parsing
    
    /// Parses user input and returns a URL if it's a valid URL
    /// Handles:
    /// - Full URLs (https://example.com)
    /// - Partial URLs (example.com, www.example.com)
    /// - IP addresses (192.168.1.1)
    func parseInput(_ input: String) -> URL? {
        let trimmed = input.trimmingCharacters(in: .whitespaces)
        
        // Check if it contains spaces (likely a search query)
        if trimmed.contains(" ") {
            return nil
        }
        
        // Try to parse as URL with scheme
        if let url = URL(string: trimmed), isValidURL(url) {
            return url
        }
        
        // Try to parse as URL without scheme
        if !trimmed.contains("://") {
            // Add https scheme and try again
            if let url = URL(string: "https://\(trimmed)"), isValidURL(url) {
                return validateDomain(url)
            }
        }
        
        // Check for IP address pattern
        if isIPAddress(trimmed) {
            if let url = URL(string: "http://\(trimmed)") {
                return url
            }
        }
        
        return nil
    }
    
    /// Builds a search URL for a given query and search engine
    func buildSearchURL(_ query: String, engine: SearchEngine) -> URL? {
        let encoded = query
            .addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
        
        let urlString = engine.baseURL + encoded
        return URL(string: urlString)
    }
    
    // MARK: - Private Helpers
    
    private func isValidURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme, let host = url.host else {
            return false
        }
        
        // Must have a valid scheme
        let validSchemes = ["http", "https", "ftp", "ftps"]
        guard validSchemes.contains(scheme) else {
            return false
        }
        
        // Host must have at least one dot (domain) or be localhost/IP
        if host == "localhost" {
            return true
        }
        
        return host.contains(".") || isIPAddress(host)
    }
    
    private func validateDomain(_ url: URL) -> URL? {
        guard let host = url.host else { return nil }
        
        // Check if host looks like a domain
        if host.contains(".") {
            // Check for common TLDs
            let components = host.split(separator: ".")
            if components.count >= 2 {
                let tld = String(components.last ?? "")
                // Basic TLD validation
                if tld.count >= 2 && tld.allSatisfy({ $0.isLetter }) {
                    return url
                }
            }
        }
        
        return nil
    }
    
    private func isIPAddress(_ string: String) -> Bool {
        let ipv4Pattern = "^(([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])$"
        
        do {
            let regex = try NSRegularExpression(pattern: ipv4Pattern, options: [])
            let range = NSRange(location: 0, length: string.utf16.count)
            return regex.firstMatch(in: string, options: [], range: range) != nil
        } catch {
            return false
        }
    }
}