(function () {
  const F = window.BankFeatures;
  window.BankWorkspace.init({
    role: 'Employee', roleIcon: 'briefcase', roleSummary: 'Daily branch service, customer operations and operational reports.', defaultSection: 'overview',
    nav: [
      { id:'overview', label:'Operations overview', shortLabel:'Home', icon:'dashboard', group:'Workspace', title:'Branch operations', description:'Monitor customers, accounts, pending work and branch activity.' },
      { id:'customers', label:'Customers', shortLabel:'Customers', icon:'users', group:'Banking operations', title:'Customer management', description:'Search, register, update and deactivate customer records.' },
      { id:'accounts', label:'Accounts', shortLabel:'Accounts', icon:'card', group:'Banking operations', title:'Account operations', description:'Search accounts, view history, freeze, close and change account type.' },
      { id:'transactions', label:'Transactions', shortLabel:'Transactions', icon:'transfer', group:'Banking operations', title:'Transaction desk', description:'Handle deposits, withdrawals, transfers, finalization and reversals.' },
      { id:'loans', label:'Loans', shortLabel:'Loans', icon:'loan', group:'Banking operations', title:'Loan services', description:'Create loans, view status and process installment payments.' },
      { id:'branches', label:'Branches', icon:'branch', group:'Organisation', title:'Branch directory', description:'Review branch information available within your access scope.' },
      { id:'employees', label:'Employee directory', icon:'briefcase', group:'Organisation', title:'Employee directory', description:'View employee information and branch history.' },
      { id:'transfers', label:'My branch transfer', icon:'transfer', group:'Organisation', title:'Employee transfer request', description:'Request a transfer to another branch and follow the approval workflow.' },
      { id:'reports', label:'Operational reports', icon:'reports', group:'Insights', title:'Operational reports', description:'Read the reporting views allowed for the Employee role.' },
      { id:'profile', label:'Profile & security', icon:'shield', group:'Account', title:'Profile and security', description:'Review your logged-in identity and effective application roles.' }
    ],
    sections: { overview:F.sections.staffOverview, customers:F.sections.customers, accounts:F.sections.staffAccounts, transactions:F.sections.staffTransactions, loans:F.sections.staffLoans, branches:F.sections.branches, employees:F.sections.employees, transfers:F.sections.transfers, reports:F.sections.reports, profile:F.sections.profile },
    actions: F.actions
  });
})();
