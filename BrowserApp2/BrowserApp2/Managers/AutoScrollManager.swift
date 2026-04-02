import SwiftUI
import WebKit
import Foundation
import UIKit


class AutoScrollManager {
    private var displayLink: CADisplayLink?
    private weak var scrollView: UIScrollView?
    private var currentSpeed: Double = 1.0
    
    // MARK: - Public Interface
    
    func startAutoScroll(webView: WKWebView?, speed: Double) {
        guard let webView = webView else { return }
        
        self.scrollView = webView.scrollView
        self.currentSpeed = speed
        
        // Create display link for smooth 60fps scrolling
        displayLink = CADisplayLink(
            target: self,
            selector: #selector(updateScroll)
        )
        displayLink?.add(to: .main, forMode: .common)
    }
    
    func stopAutoScroll() {
        displayLink?.invalidate()
        displayLink = nil
    }
    
    func updateSpeed(_ speed: Double) {
        currentSpeed = speed
    }
    
    // MARK: - Private Methods
    
    @objc private func updateScroll() {
        guard let scrollView = scrollView else { return }
        
        let maxOffset = scrollView.contentSize.height - scrollView.bounds.height
        let newOffset = scrollView.contentOffset.y + CGFloat(currentSpeed)
        
        // Stop at bottom
        if newOffset >= maxOffset {
            stopAutoScroll()
            return
        }
        
        // Smooth update without animation
        var offset = scrollView.contentOffset
        offset.y = newOffset
        scrollView.contentOffset = offset
    }
}