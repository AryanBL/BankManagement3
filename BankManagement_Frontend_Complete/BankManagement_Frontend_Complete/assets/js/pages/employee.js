(function () {
  const F = window.BankFeatures;
  window.BankWorkspace.init({
    role: 'Employee', roleIcon: 'briefcase', roleSummary: 'Branch-scoped service access plus a separate personal banking portfolio.', defaultSection: 'overview',
    nav: [
      { id:'overview', label:'Operations overview', shortLabel:'Home', icon:'dashboard', group:'Workspace', title:'Branch operations', description:'Monitor customers, branch-scoped accounts, loans and operational activity.' },
      { id:'customers', label:'Customers', shortLabel:'Customers', icon:'users', group:'Branch operations', title:'Customer management', description:'Search, register, update and deactivate customer records.' },
      { id:'accounts', label:'Branch accounts', shortLabel:'Branch', icon:'card', group:'Branch operations', title:'Current branch accounts', description:'View account details and history, then perform permitted account-management actions for your active branch. Financial transactions remain owner-only.' },
      { id:'loans', label:'Branch loans', shortLabel:'Loans', icon:'loan', group:'Branch operations', title:'Current branch loans', description:'Create loans and inspect loan details and installment schedules for your active branch.' },
      { id:'my-accounts', label:'My accounts', shortLabel:'My accounts', icon:'wallet', group:'Personal banking', title:'My personal accounts', description:'Accounts owned by the CustomerID linked to your employee login.' },
      { id:'transactions', label:'My transactions', shortLabel:'Transfer', icon:'transfer', group:'Personal banking', title:'My transactions', description:'Deposit, withdraw and transfer only from your own accounts.' },
      { id:'my-loans', label:'My loans', shortLabel:'My loans', icon:'loan', group:'Personal banking', title:'My personal loans', description:'Review and pay only installments belonging to your borrower profile.' },
      { id:'branches', label:'Branches', icon:'branch', group:'Organisation', title:'Branch directory', description:'Review branch information available within your access scope.' },
      { id:'employees', label:'Employee directory', icon:'briefcase', group:'Organisation', title:'Employee directory', description:'View employee information and branch history.' },
      { id:'transfers', label:'My branch transfer', icon:'transfer', group:'Organisation', title:'Employee transfer request', description:'Request a transfer to another branch and follow the approval workflow.' },
      { id:'reports', label:'Operational reports', icon:'reports', group:'Insights', title:'Operational reports', description:'Read the reporting views allowed for the Employee role. Branch-aware reports are scoped automatically.' },
      { id:'profile', label:'Profile & security', icon:'shield', group:'Account', title:'Profile and security', description:'Review your logged-in identity and effective application roles.' }
    ],
    sections: {
      overview:F.sections.staffOverview,
      customers:F.sections.customers,
      accounts:F.sections.staffAccounts,
      loans:F.sections.staffLoans,
      'my-accounts':F.sections.staffOwnAccounts,
      transactions:F.sections.staffTransactions,
      'my-loans':F.sections.staffOwnLoans,
      branches:F.sections.branches,
      employees:F.sections.employees,
      transfers:F.sections.transfers,
      reports:F.sections.reports,
      profile:F.sections.profile
    },
    actions: F.actions
  });
})();
