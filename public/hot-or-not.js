// Hot or Not - Resolve Modal and Copy Curl Command

(function () {
  function openResolveModal() {
    const modal = document.getElementById("resolve-modal");
    if (modal) {
      modal.style.display = "flex";
      const input = document.getElementById("changeset_url");
      if (input) {
        input.focus();
      }
    }
  }

  function closeResolveModal() {
    const modal = document.getElementById("resolve-modal");
    if (modal) {
      modal.style.display = "none";
    }
  }

  function getCsrfToken() {
    const meta = document.querySelector('meta[name="csrf-token"]');
    return meta ? meta.getAttribute("content") : "";
  }

  function copyToClipboard(text) {
    if (navigator.clipboard && navigator.clipboard.writeText) {
      return navigator.clipboard.writeText(text);
    }
    // Fallback for older browsers or when clipboard API fails
    const textarea = document.createElement("textarea");
    textarea.value = text;
    textarea.style.position = "fixed";
    textarea.style.opacity = "0";
    document.body.appendChild(textarea);
    textarea.select();
    try {
      document.execCommand("copy");
      document.body.removeChild(textarea);
      return Promise.resolve();
    } catch (err) {
      document.body.removeChild(textarea);
      return Promise.reject(err);
    }
  }

  async function handleCopyCurlClick(e) {
    const btn = e.currentTarget;
    const patchId = btn.getAttribute("data-patch-id");
    if (!patchId || btn.disabled) {
      return;
    }

    const originalText = btn.textContent.trim();
    btn.disabled = true;
    btn.textContent = "Copying...";
    btn.classList.add("loading");
    btn.classList.remove("copied", "error");

    try {
      const response = await fetch(
        "/hot-or-not/" + patchId + "/generate-download-token",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "X-CSRF-Token": getCsrfToken(),
            Accept: "application/json",
          },
          credentials: "same-origin",
        }
      );

      if (!response.ok) {
        const text = await response.text();
        /* eslint-disable-next-line no-console */
        console.error("Response:", response.status, text);
        throw new Error("Failed: " + response.status);
      }

      const data = await response.json();
      if (!data.curl_command) {
        throw new Error("No curl command in response");
      }

      await copyToClipboard(data.curl_command);

      btn.textContent = "Copied!";
      btn.classList.remove("loading");
      btn.classList.add("copied");

      setTimeout(function () {
        btn.textContent = originalText;
        btn.classList.remove("copied");
        btn.disabled = false;
      }, 2000);
    } catch (err) {
      /* eslint-disable-next-line no-console */
      console.error("Copy curl command failed:", err);
      btn.textContent = "Failed";
      btn.classList.remove("loading");
      btn.classList.add("error");

      setTimeout(function () {
        btn.textContent = originalText;
        btn.classList.remove("error");
        btn.disabled = false;
      }, 2000);
    }
  }

  document.addEventListener("DOMContentLoaded", function () {
    const openBtn = document.getElementById("open-resolve-modal");
    if (openBtn) {
      openBtn.addEventListener("click", openResolveModal);
    }

    const closeButtons = document.querySelectorAll("[data-close-modal]");
    closeButtons.forEach(function (btn) {
      btn.addEventListener("click", closeResolveModal);
    });

    const modal = document.getElementById("resolve-modal");
    if (modal) {
      modal.addEventListener("click", function (e) {
        if (e.target === modal) {
          closeResolveModal();
        }
      });
    }

    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape") {
        closeResolveModal();
      }
    });

    const copyBtn = document.querySelector(".copy-curl-btn");
    if (copyBtn) {
      copyBtn.addEventListener("click", handleCopyCurlClick);
    }
  });
})();
