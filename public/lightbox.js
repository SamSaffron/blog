/**
 * Simple Lightbox for Blog Images
 * Vanilla JavaScript implementation
 */
(function() {
  'use strict';

  let currentOverlay = null;

  function createOverlay() {
    const overlay = document.createElement('div');
    overlay.className = 'lightbox-overlay';
    
    const closeButton = document.createElement('button');
    closeButton.className = 'lightbox-close';
    closeButton.innerHTML = '×';
    closeButton.setAttribute('aria-label', 'Close lightbox');
    
    const img = document.createElement('img');
    img.alt = '';
    
    const info = document.createElement('div');
    info.className = 'lightbox-info';
    
    overlay.appendChild(closeButton);
    overlay.appendChild(img);
    overlay.appendChild(info);
    
    return overlay;
  }

  function openLightbox(imageUrl, title, details) {
    // Create overlay if it doesn't exist
    if (!currentOverlay) {
      currentOverlay = createOverlay();
      document.body.appendChild(currentOverlay);
      
      // Close on overlay click (but not on image click)
      currentOverlay.addEventListener('click', function(e) {
        if (e.target === currentOverlay || e.target.className === 'lightbox-close') {
          closeLightbox();
        }
      });
      
      // Close on ESC key
      document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape' && currentOverlay && currentOverlay.classList.contains('active')) {
          closeLightbox();
        }
      });
    }
    
    // Set image and info
    const img = currentOverlay.querySelector('img');
    const info = currentOverlay.querySelector('.lightbox-info');
    
    img.src = imageUrl;
    img.alt = title || '';
    
    if (title || details) {
      let infoHtml = '';
      if (title) {
        infoHtml += '<span class="filename">' + escapeHtml(title) + '</span>';
      }
      if (details) {
        infoHtml += '<span class="details">' + escapeHtml(details) + '</span>';
      }
      info.innerHTML = infoHtml;
      info.style.display = 'block';
    } else {
      info.style.display = 'none';
    }
    
    // Prevent body scroll
    document.body.style.overflow = 'hidden';
    
    // Show overlay with animation (need to wait for display change)
    currentOverlay.classList.add('active');
    requestAnimationFrame(function() {
      requestAnimationFrame(function() {
        // Trigger reflow to ensure display change is applied before opacity transition
      });
    });
  }

  function closeLightbox() {
    if (!currentOverlay) return;
    
    currentOverlay.classList.remove('active');
    
    // Re-enable body scroll
    document.body.style.overflow = '';
    
    // Remove overlay after animation
    setTimeout(function() {
      if (currentOverlay && !currentOverlay.classList.contains('active')) {
        const img = currentOverlay.querySelector('img');
        img.src = '';
      }
    }, 300);
  }

  function escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  function initLightbox() {
    // Find all lightbox links
    const lightboxLinks = document.querySelectorAll('a.lightbox');
    
    lightboxLinks.forEach(function(link) {
      link.addEventListener('click', function(e) {
        e.preventDefault();
        
        const imageUrl = link.getAttribute('href');
        const img = link.querySelector('img');
        const title = link.getAttribute('title') || (img ? img.getAttribute('alt') : '');
        
        // Get details from meta section if available
        let details = '';
        const wrapper = link.closest('.lightbox-wrapper');
        if (wrapper) {
          const metaInfo = wrapper.querySelector('.meta .informations');
          if (metaInfo) {
            details = metaInfo.textContent.trim();
          }
        }
        
        openLightbox(imageUrl, title, details);
      });
    });
  }

  // Initialize when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initLightbox);
  } else {
    initLightbox();
  }

})();
