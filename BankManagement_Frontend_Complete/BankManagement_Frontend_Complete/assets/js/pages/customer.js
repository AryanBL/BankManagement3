(function () {
  const F = window.BankFeatures;
  window.BankWorkspace.init({
    role: 'Customer', roleIcon: 'user', roleSummary: 'Personal accounts, transfers, withdrawals and loan payments.', defaultSection: 'overview',
    nav: [
      { id:'overview', label:'Overview', shortLabel:'Home', icon:'dashboard', group:'Personal banking', title:'Good to see you', description:'A clear view of your accounts, balances and recent activity.' },
      { id:'accounts', label:'My accounts', shortLabel:'Accounts', icon:'card', group:'Personal banking', title:'My accounts', description:'Review account details, balances, status and transaction history.' },
      { id:'transactions', label:'Transfers & activity', shortLabel:'Transfers', icon:'transfer', group:'Money movement', title:'Transfers and transaction activity', description:'Move funds, request withdrawals and review account history.' },
      { id:'loans', label:'Loans & installments', shortLabel:'Loans', icon:'loan', group:'Money movement', title:'Loans and installments', description:'Check a loan status and pay eligible installments.' },
      { id:'profile', label:'Profile & security', shortLabel:'Profile', icon:'shield', group:'Account', title:'Profile and session security', description:'Review your authenticated identity, effective roles and session status.' }
    ],
    sections: { overview:F.sections.customerOverview, accounts:F.sections.customerAccounts, transactions:F.sections.customerTransactions, loans:F.sections.customerLoans, profile:F.sections.profile },
    actions: F.actions
  });
})();
