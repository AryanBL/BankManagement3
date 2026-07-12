(function () {
  const F = window.BankFeatures;
  window.BankWorkspace.init({
    role: 'HighAdmin', roleIcon: 'shield', roleSummary: 'Enterprise-wide oversight plus a separate personal banking portfolio.', defaultSection: 'overview',
    nav: [
      { id:'overview', label:'Executive overview', shortLabel:'Home', icon:'dashboard', group:'Executive', title:'Executive banking overview', description:'High-level visibility across branches, customers, accounts, employees and financial reports.' },
      { id:'managers', label:'Manager governance', shortLabel:'Managers', icon:'briefcase', group:'Executive', title:'Manager governance', description:'Hire, promote, downgrade, suspend, terminate and replace branch managers.' },
      { id:'customers', label:'Customers', shortLabel:'Customers', icon:'users', group:'Enterprise operations', title:'Customer management', description:'Manage the full customer directory and customer lifecycle.' },
      { id:'accounts', label:'All accounts', shortLabel:'Accounts', icon:'card', group:'Enterprise operations', title:'All bank accounts', description:'View and manage eligible accounts across every branch. Financial transactions remain restricted to the account owner.' },
      { id:'loans', label:'All loans', shortLabel:'Loans', icon:'loan', group:'Enterprise operations', title:'All bank loans', description:'Create and inspect loans and installment schedules across all branches.' },
      { id:'my-accounts', label:'My accounts', shortLabel:'My accounts', icon:'wallet', group:'Personal banking', title:'My personal accounts', description:'Accounts owned by the CustomerID linked to the HighAdmin login.' },
      { id:'transactions', label:'My transactions', shortLabel:'Transfer', icon:'transfer', group:'Personal banking', title:'My transactions', description:'HighAdmin privileges do not bypass account ownership for financial transactions.' },
      { id:'my-loans', label:'My loans', shortLabel:'My loans', icon:'loan', group:'Personal banking', title:'My personal loans', description:'Review and pay only installments belonging to the HighAdmin customer profile.' },
      { id:'employees', label:'Employees', icon:'userPlus', group:'Organisation', title:'Workforce administration', description:'Manage employee records, application accounts, titles and employment status.' },
      { id:'transfers', label:'Employee transfers', icon:'transfer', group:'Organisation', title:'Employee transfer workflow', description:'Request employee transfers and review the two-manager approval process.' },
      { id:'branches', label:'Branches', icon:'branch', group:'Organisation', title:'Branch network', description:'Review all branches and their operating details.' },
      { id:'reports', label:'All reports', icon:'reports', group:'Governance & audit', title:'Role-protected reports', description:'Access operational, administrative and HighAdmin reporting views.' },
      { id:'audit', label:'Audit & ledger', icon:'shield', group:'Governance & audit', title:'Audit trail and branch ledger', description:'Review safe audit records and financial ledger reporting views.' },
      { id:'maintenance', label:'Maintenance', icon:'settings', group:'Governance & audit', title:'System maintenance controls', description:'Process all branches or select one branch for manual overdue-loan processing.' },
      { id:'profile', label:'Profile & security', icon:'user', group:'Account', title:'HighAdmin identity', description:'Review the current session and effective roles.' }
    ],
    sections: {
      overview:F.sections.executiveOverview,
      managers:F.sections.managers,
      customers:F.sections.customers,
      accounts:F.sections.staffAccounts,
      loans:F.sections.staffLoans,
      'my-accounts':F.sections.staffOwnAccounts,
      transactions:F.sections.staffTransactions,
      'my-loans':F.sections.staffOwnLoans,
      employees:F.sections.employees,
      transfers:F.sections.transfers,
      branches:F.sections.branches,
      reports:F.sections.reports,
      audit:F.sections.audit,
      maintenance:F.sections.maintenance,
      profile:F.sections.profile
    },
    actions: F.actions
  });
})();
