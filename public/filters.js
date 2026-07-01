// Progressive enhancement for the event filters. Without this script every
// control is a real link/form that navigates normally; with it, filtering
// happens via AJAX against /events and the URL is kept in sync so views stay
// shareable. The filter controls live outside [data-events], so this script
// updates the count badge and applied-chips row itself after each change.
(function () {
  "use strict";

  var filters = document.querySelector("[data-filters]");
  var results = document.querySelector("[data-events]");
  if (!filters || !results) return;

  var dropdown = filters.querySelector("[data-source-filter]");
  var options = Array.prototype.slice.call(filters.querySelectorAll(".source-option"));
  var badge = filters.querySelector("[data-source-count]");
  var applied = filters.querySelector("[data-applied]");
  var search = filters.querySelector("[data-search]");
  var skeleton = document.querySelector("[data-skeleton]");
  var searchTimer = null;

  // The source options whose aria-checked is currently "true".
  function selected() {
    return options.filter(function (option) {
      return option.getAttribute("aria-checked") === "true";
    });
  }

  function setChecked(option, value) {
    option.setAttribute("aria-checked", value ? "true" : "false");
  }

  // Builds the query string from the current selection and search state.
  function queryString() {
    var params = new URLSearchParams();

    var slugs = selected().map(function (option) {
      return option.dataset.source;
    });
    if (slugs.length) params.set("source", slugs.join(","));

    if (search && search.value.trim()) params.set("q", search.value.trim());

    return params.toString();
  }

  // Reflects the current selection onto the count badge and the applied-chips
  // row (both live outside the AJAX-swapped results region).
  function render() {
    var chosen = selected();

    if (badge) {
      badge.textContent = String(chosen.length);
      badge.hidden = chosen.length === 0;
    }

    if (applied) {
      applied.querySelectorAll(".applied-chip").forEach(function (chip) {
        chip.remove();
      });
      chosen.forEach(function (option) {
        var chip = document.createElement("a");
        chip.className = "applied-chip";
        chip.href = "#";
        chip.dataset.source = option.dataset.source;
        chip.setAttribute("aria-label", "Remove " + option.dataset.label + " filter");
        chip.innerHTML =
          option.dataset.label +
          '<span class="applied-chip-x" aria-hidden="true">×</span>';
        applied.appendChild(chip);
      });
      applied.hidden = chosen.length === 0;
    }
  }

  // Fetches the filtered list fragment and swaps it into the results region.
  // The fetch hits the calendar API server-side, so show skeleton placeholders
  // that mirror the events layout while it's in flight. On a network error,
  // restore the previous list rather than leaving the skeleton up.
  function refresh() {
    var qs = queryString();
    var previous = results.innerHTML;
    if (skeleton) results.innerHTML = skeleton.innerHTML;
    results.setAttribute("aria-busy", "true");
    fetch("/events" + (qs ? "?" + qs : ""), {
      headers: { "X-Requested-With": "fetch" }
    })
      .then(function (response) {
        return response.text();
      })
      .then(function (html) {
        results.innerHTML = html;
      })
      .catch(function () {
        results.innerHTML = previous;
      })
      .then(function () {
        results.removeAttribute("aria-busy");
      });
  }

  // Pushes the matching "/events" URL so the address bar reflects the filters
  // and back/forward works, then refreshes the list.
  function apply() {
    var qs = queryString();
    history.pushState(null, "", qs ? "/events?" + qs : "/events");
    render();
    refresh();
  }

  // Reflects the current URL onto the options and search box (used on popstate).
  function syncFromUrl() {
    var params = new URLSearchParams(window.location.search);
    var slugs = (params.get("source") || "").split(",");
    options.forEach(function (option) {
      setChecked(option, slugs.indexOf(option.dataset.source) !== -1);
    });
    if (search) search.value = params.get("q") || "";
    render();
  }

  // Toggle a source from within the dropdown.
  options.forEach(function (option) {
    option.addEventListener("click", function (event) {
      event.preventDefault();
      setChecked(option, option.getAttribute("aria-checked") !== "true");
      apply();
    });
  });

  // Applied chips are rebuilt on every render, so handle their clicks via
  // delegation on the stable container.
  if (applied) {
    applied.addEventListener("click", function (event) {
      var chip = event.target.closest(".applied-chip");
      if (chip) {
        event.preventDefault();
        options.forEach(function (option) {
          if (option.dataset.source === chip.dataset.source) setChecked(option, false);
        });
        apply();
      }
    });
  }

  var selectAll = filters.querySelector("[data-select-all]");
  if (selectAll) {
    selectAll.addEventListener("click", function (event) {
      event.preventDefault();
      options.forEach(function (option) {
        setChecked(option, true);
      });
      apply();
    });
  }

  var clearSources = filters.querySelector("[data-clear-sources]");
  if (clearSources) {
    clearSources.addEventListener("click", function (event) {
      event.preventDefault();
      options.forEach(function (option) {
        setChecked(option, false);
      });
      apply();
    });
  }

  if (search) {
    search.addEventListener("input", function () {
      window.clearTimeout(searchTimer);
      searchTimer = window.setTimeout(apply, 250);
    });
  }

  var form = filters.querySelector(".filter-search-form");
  if (form) {
    form.addEventListener("submit", function (event) {
      event.preventDefault();
      window.clearTimeout(searchTimer);
      apply();
    });
  }

  // Close the dropdown on an outside click or Escape (native <details> only
  // closes via its own summary otherwise).
  if (dropdown) {
    document.addEventListener("click", function (event) {
      if (dropdown.open && !dropdown.contains(event.target)) dropdown.open = false;
    });
    dropdown.addEventListener("keydown", function (event) {
      if (event.key === "Escape") dropdown.open = false;
    });
  }

  window.addEventListener("popstate", function () {
    syncFromUrl();
    refresh();
  });
})();
