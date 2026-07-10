(function () {
  const F = window.BankFeatures;
  window.BankWorkspace.init({
    role: 'HighAdmin', roleIcon: 'shield', roleSummary: 'Enterprise oversight, manager governance, access control and audit visibility.', defaultSection: 'overview',
    nav: [
      { id:'overview', label:'Executive overview', shortLabel:'Home', icon:'dashboard', group:'Executive', title:'Executive banking overview', description:'High-level visibility across branches, customers, accounts, employees and financial reports.' },
      { id:'managers', label:'Manager governance', shortLabel:'Managers', icon:'briefcase', group:'Executive', title:'Manager governance', description:'Hire, promote, downgrade, suspend, terminate and replace branch managers.' },
      { id:'customers', label:'Customers', shortLabel:'Customers', icon:'users', group:'Banking operations', title:'Customer management', description:'Manage the full customer directory and customer lifecycle.' },
      { id:'accounts', label:'Accounts', shortLabel:'Accounts', icon:'card', group:'Banking operations', title:'Account oversight', description:'Review and administer account status, history and restrictions.' },
      { id:'transactions', label:'Transactions', shortLabel:'Transactions', icon:'transfer', group:'Banking operations', title:'Transaction oversight', description:'Supervise financial transactions, pending queues, finalization and reversals.' },
      { id:'loans', label:'Loans', icon:'loan', group:'Banking operations', title:'Loan oversight', description:'Create loans, inspect status, collect installments and process overdue records.' },
      { id:'employees', label:'Employees', icon:'userPlus', group:'Organisation', title:'Workforce administration', description:'Manage employee records, application accounts, titles and employment status.' },
      { id:'transfers', label:'Employee transfers', icon:'transfer', group:'Organisation', title:'Employee transfer workflow', description:'Request employee transfers and review the two-manager approval process.' },
      { id:'branches', label:'Branches', icon:'branch', group:'Organisation', title:'Branch network', description:'Review all branches and their operating details.' },
      { id:'reports', label:'All reports', icon:'reports', group:'Governance & audit', title:'Role-protected reports', description:'Access operational, administrative and HighAdmin reporting views.' },
      { id:'audit', label:'Audit & ledger', icon:'shield', group:'Governance & audit', title:'Audit trail and branch ledger', description:'Review safe audit records and financial ledger reporting views.' },
      { id:'maintenance', label:'Maintenance', icon:'settings', group:'Governance & audit', title:'System maintenance controls', description:'Run authorized transaction, loan and account maintenance procedures.' },
      { id:'profile', label:'Profile & security', icon:'user', group:'Account', title:'HighAdmin identity', description:'Review the current session and inherited effective roles.' }
    ],
    sections: { overview:F.sections.executiveOverview, managers:F.sections.managers, customers:F.sections.customers, accounts:F.sections.staffAccounts, transactions:F.sections.staffTransactions, loans:F.sections.staffLoans, employees:F.sections.employees, transfers:F.sections.transfers, branches:F.sections.branches, reports:F.sections.reports, audit:F.sections.audit, maintenance:F.sections.maintenance, profile:F.sections.profile },
    actions: F.actions
  });
})();
