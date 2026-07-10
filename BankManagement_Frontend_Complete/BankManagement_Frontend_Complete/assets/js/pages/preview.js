(function () {
  // The selector itself is neutral; a role is set only after a card is chosen.
  window.BankSession.stopPreview();
  document.querySelectorAll('[data-preview-role]').forEach((button) => {
    button.addEventListener('click', () => {
      const role = button.dataset.previewRole;
      window.BankSession.startPreview(role);
      location.href = window.BankConfig.PAGE_BY_ROLE[role];
    });
  });
  document.querySelector('#exit-preview')?.addEventListener('click', () => {
    window.BankSession.stopPreview(); location.href = 'index.html';
  });
})();
