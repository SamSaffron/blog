/**
 * Copy Code Button for Blog Code Blocks
 * Vanilla JavaScript implementation
 */
(function() {
  'use strict';

  function extractCodeText(codeElement) {
    // Handle GitHub blob oneboxes with line numbers
    const lines = codeElement.querySelectorAll('ol.lines li');
    if (lines.length > 0) {
      return Array.from(lines)
        .map(function(li) {
          return li.textContent.trim();
        })
        .join('\n');
    }
    
    // Handle regular code blocks
    return codeElement.textContent;
  }

  function copyToClipboard(text) {
    // Modern Clipboard API
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text);
    }
    
    // Fallback for older browsers
    return new Promise(function(resolve, reject) {
      const textArea = document.createElement('textarea');
      textArea.value = text;
      textArea.style.position = 'fixed';
      textArea.style.left = '-999999px';
      textArea.style.top = '-999999px';
      document.body.appendChild(textArea);
      textArea.focus();
      textArea.select();
      
      try {
        const successful = document.execCommand('copy');
        textArea.remove();
        if (successful) {
          resolve();
        } else {
          reject(new Error('Copy command failed'));
        }
      } catch (err) {
        textArea.remove();
        reject(err);
      }
    });
  }

  function createCopyButton() {
    const button = document.createElement('button');
    button.className = 'copy-code-button';
    button.textContent = 'Copy';
    button.setAttribute('aria-label', 'Copy code to clipboard');
    return button;
  }

  function handleCopyClick(button, codeElement) {
    const codeText = extractCodeText(codeElement);
    
    copyToClipboard(codeText)
      .then(function() {
        button.textContent = 'Copied!';
        button.classList.add('copied');
        
        setTimeout(function() {
          button.textContent = 'Copy';
          button.classList.remove('copied');
        }, 2000);
      })
      .catch(function(err) {
        console.error('Failed to copy code:', err);
        button.textContent = 'Error';
        
        setTimeout(function() {
          button.textContent = 'Copy';
        }, 2000);
      });
  }

  function addCopyButtons() {
    // Find all code blocks (both regular and onebox)
    const codeBlocks = document.querySelectorAll('pre > code, pre.onebox code');
    
    codeBlocks.forEach(function(codeElement) {
      const preElement = codeElement.closest('pre');
      
      // Skip if button already exists
      if (preElement.querySelector('.copy-code-button')) {
        return;
      }
      
      // Create and add button
      const button = createCopyButton();
      button.addEventListener('click', function(e) {
        e.preventDefault();
        handleCopyClick(button, codeElement);
      });
      
      preElement.appendChild(button);
    });
  }

  // Initialize when DOM is ready
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', addCopyButtons);
  } else {
    addCopyButtons();
  }

})();
