import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/api_exception.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/formatters.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/confirm_dialog.dart';
import '../../../shared/widgets/labeled_field.dart';
import '../../../shared/widgets/loading_shimmer.dart';
import '../../../shared/widgets/section_title.dart';
import '../../auth/providers/auth_provider.dart';
import '../../invoices/data/invoice_models.dart';
import '../../invoices/providers/invoice_providers.dart';
import '../../shell/widgets/app_topbar.dart';

// -----------------------------------------------------------------------------
// The INVOICE_SETTINGS row: the letterhead, bank block, declaration, footer and
// defaults every tax invoice PDF is rendered from. It is the feature's
// prerequisite — the server refuses to issue an invoice when the row is empty,
// because without a seller GSTIN it cannot decide CGST + SGST vs IGST.
//
// Admin-only (the row holds the company's bank account number, so billing a
// customer is not the same right as re-pointing where that customer pays). The
// account number is never logged, never echoed into a snackbar and never put in
// an error message.
//
// PUT /invoices/settings REPLACES the whole row and REJECTS unknown keys, so
// every key the Joi schema declares is round-tripped here — including the logo
// and signature storage keys this screen cannot edit. Dropping them would erase
// the letterhead graphics on the next save.
// -----------------------------------------------------------------------------

/// GST state codes, mirroring the server's `STATE_CODES` table (`utils/gst.js`)
/// verbatim. The first two digits of a GSTIN are the state, and the seller's
/// state is what the INTRA/INTER split turns on.
const String _stateCodeTable =
    '01=Jammu and Kashmir|02=Himachal Pradesh|03=Punjab|04=Chandigarh|'
    '05=Uttarakhand|06=Haryana|07=Delhi|08=Rajasthan|09=Uttar Pradesh|'
    '10=Bihar|11=Sikkim|12=Arunachal Pradesh|13=Nagaland|14=Manipur|'
    '15=Mizoram|16=Tripura|17=Meghalaya|18=Assam|19=West Bengal|20=Jharkhand|'
    '21=Odisha|22=Chhattisgarh|23=Madhya Pradesh|24=Gujarat|25=Daman and Diu|'
    '26=Dadra and Nagar Haveli and Daman and Diu|27=Maharashtra|'
    '28=Andhra Pradesh (Before Division)|29=Karnataka|30=Goa|31=Lakshadweep|'
    '32=Kerala|33=Tamil Nadu|34=Puducherry|35=Andaman and Nicobar Islands|'
    '36=Telangana|37=Andhra Pradesh|38=Ladakh|97=Other Territory|'
    '99=Centre Jurisdiction';

final Map<String, String> _stateNameByCode = {
  for (final entry in _stateCodeTable.split('|'))
    entry.substring(0, 2): entry.substring(3),
};

/// Superseded by a live code (UT merger, Andhra bifurcation). A GSTIN issued
/// under one is still valid, but a typed state NAME must resolve to the live
/// code — the same exclusion the server's NAME_TO_CODE makes.
const Set<String> _legacyStateCodes = {'25', '28'};

/// Renames and pre-merger names that turn up in real party masters.
const Map<String, String> _stateNameAliases = {
  'orissa': '21',
  'pondicherry': '34',
  'uttaranchal': '05',
  'nctofdelhi': '07',
  'newdelhi': '07',
  'delhinct': '07',
  'jammukashmir': '01',
  'dadranagarhaveli': '26',
  'damandiu': '26',
  'damananddiu': '26',
  'andaman': '35',
  'andamannicobar': '35',
  'chattisgarh': '22',
};

/// Case, punctuation and '&' are noise on a hand-typed state name.
String _normalizeStateName(String name) => name
    .toLowerCase()
    .replaceAll('&', 'and')
    .replaceAll(RegExp('[^a-z0-9]'), '');

final Map<String, String> _stateCodeByName = {
  for (final e in _stateNameByCode.entries)
    if (!_legacyStateCodes.contains(e.key)) _normalizeStateName(e.value): e.key,
  ..._stateNameAliases,
};

/// 15 chars: 2 state digits + 10 PAN chars + entity code + 'Z' slot + checksum.
final RegExp _gstinPattern = RegExp(
  r'^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]{3}$',
);

final RegExp _emailPattern = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// The state code a GSTIN declares, or null when it is not a readable GSTIN.
String? _stateCodeFromGstin(String gstin) {
  final value = gstin.trim().toUpperCase();
  if (!_gstinPattern.hasMatch(value)) return null;
  final code = value.substring(0, 2);
  return _stateNameByCode.containsKey(code) ? code : null;
}

class InvoiceSettingsScreen extends ConsumerStatefulWidget {
  const InvoiceSettingsScreen({super.key});

  @override
  ConsumerState<InvoiceSettingsScreen> createState() =>
      _InvoiceSettingsScreenState();
}

class _InvoiceSettingsScreenState extends ConsumerState<InvoiceSettingsScreen> {
  final _company = _CompanyFields();
  final _bank = _BankFields();
  final _footer = _FooterFields();
  final _defaults = _DefaultFields();
  final List<TextEditingController> _declaration = [];

  /// Storage keys, not URLs, and there is no upload endpoint on this module —
  /// they are held verbatim so a save cannot erase the letterhead graphics.
  String _logoKey = '';
  String _signatureKey = '';

  /// Whether the row has ever been written. False renders the "not configured"
  /// state, whose fields show examples as HINTS — never as silent values.
  bool _configured = false;
  bool _hydrated = false;
  bool _saving = false;
  bool _showErrors = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    // Reading the provider starts the fetch; if it already holds data (a return
    // visit), hydrate synchronously so the form never flashes a skeleton.
    final current = ref.read(invoiceSettingsProvider);
    if (current case AsyncData(:final value)) {
      _hydrate(value);
      _hydrated = true;
    }
  }

  @override
  void dispose() {
    for (final c in [
      ..._company.all,
      ..._bank.all,
      ..._footer.all,
      ..._defaults.all,
      ..._declaration,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _hydrate(InvoiceSettings? settings) {
    final v = settings ?? const InvoiceSettings();
    _configured = settings != null;
    _company.name.text = v.company.name;
    _company.address.text = v.company.addressLines.join('\n');
    _company.gstin.text = v.company.gstin;
    _company.state.text = v.company.state;
    _company.email.text = v.company.email;
    _company.website.text = v.company.website;
    _company.signFor.text = v.company.signFor;
    _bank.name.text = v.bank.name;
    _bank.accountNo.text = v.bank.accountNo;
    _bank.branchIfsc.text = v.bank.branchIfsc;
    _footer.jurisdiction.text = v.jurisdictionText;
    _footer.computerGenerated.text = v.computerGeneratedText;
    _defaults.sellerGstin.text = v.sellerGstin;
    _defaults.gstRate.text = v.gstRate == null ? '' : pctText(v.gstRate);
    _defaults.hsnSac.text = v.defaultHsnSac;
    _defaults.serviceMode.text = v.defaultServiceMode;
    _defaults.lineTitle.text = v.defaultLineTitle;
    _setDeclaration(v.declaration);
    _logoKey = v.logoKey;
    _signatureKey = v.signatureKey;
  }

  /// Resizes the paragraph editors in place so existing rows keep their
  /// controllers (and their cursors) instead of being rebuilt wholesale.
  void _setDeclaration(List<String> paragraphs) {
    final wanted = paragraphs.isEmpty ? const [''] : paragraphs;
    while (_declaration.length > wanted.length) {
      _declaration.removeLast().dispose();
    }
    while (_declaration.length < wanted.length) {
      _declaration.add(TextEditingController());
    }
    for (var i = 0; i < wanted.length; i++) {
      _declaration[i].text = wanted[i];
    }
  }

  List<String> _addressLines() => _company.address.text
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  String get _effectiveSellerGstin {
    final seller = _defaults.sellerGstin.text.trim();
    return seller.isEmpty ? _company.gstin.text.trim() : seller;
  }

  String? _gstinError(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (value.length != 15) {
      return 'A GSTIN is exactly 15 characters — ${value.length} entered.';
    }
    if (_stateCodeFromGstin(value) == null) {
      return 'That is not a readable GSTIN. Expected 27ABCDE1234F1Z5.';
    }
    return null;
  }

  /// A warning, never a block: the pair decides CGST + SGST vs IGST on every
  /// future invoice, so a disagreement is worth saying out loud — but the state
  /// name is only printed on the letterhead, and the GSTIN is what the server
  /// actually reads.
  String? _stateWarning() {
    final code = _stateCodeFromGstin(_effectiveSellerGstin);
    final typed = _company.state.text.trim();
    if (code == null || typed.isEmpty) return null;
    final typedCode = _stateCodeByName[_normalizeStateName(typed)];
    if (typedCode == null || typedCode == code) return null;
    final gstinState = _stateNameByCode[code] ?? code;
    return 'The GSTIN starts with $code ($gstinState) but the state reads '
        '"$typed". The GSTIN wins: every invoice to a $gstinState customer '
        'will carry CGST + SGST, and every other one IGST. Check the pair '
        'before you save.';
  }

  _FormErrors _errors() {
    final email = _company.email.text.trim();
    final rate = _defaults.gstRate.text.trim();
    final rateValue = double.tryParse(rate);
    return _FormErrors(
      companyGstin: _gstinError(_company.gstin.text),
      sellerGstin: _gstinError(_defaults.sellerGstin.text),
      email: email.isEmpty || _emailPattern.hasMatch(email)
          ? null
          : 'Enter a valid email address, or leave it blank.',
      address: _addressLines().length > 10
          ? 'At most 10 address lines fit the letterhead.'
          : null,
      gstRate: rate.isEmpty
          ? null
          : rateValue == null
          ? 'Enter a number, e.g. 18.'
          : (rateValue < 0 || rateValue > 100)
          ? 'A GST rate is between 0 and 100.'
          : null,
      stateWarning: _stateWarning(),
    );
  }

  InvoiceSettings _collect() {
    final paragraphs = [for (final c in _declaration) c.text.trim()]
      ..removeWhere((p) => p.isEmpty);
    return InvoiceSettings(
      company: InvoiceCompanySettings(
        name: _company.name.text.trim(),
        addressLines: _addressLines(),
        gstin: _company.gstin.text.trim().toUpperCase(),
        state: _company.state.text.trim(),
        email: _company.email.text.trim(),
        website: _company.website.text.trim(),
        signFor: _company.signFor.text.trim(),
      ),
      bank: InvoiceBankSettings(
        name: _bank.name.text.trim(),
        accountNo: _bank.accountNo.text.trim(),
        branchIfsc: _bank.branchIfsc.text.trim(),
      ),
      declaration: paragraphs,
      jurisdictionText: _footer.jurisdiction.text.trim(),
      computerGeneratedText: _footer.computerGenerated.text.trim(),
      sellerGstin: _defaults.sellerGstin.text.trim().toUpperCase(),
      // Blank means "let the server decide" — toJson then omits the key, which
      // the Joi number field requires (it rejects an explicit null).
      gstRate: double.tryParse(_defaults.gstRate.text.trim()),
      defaultHsnSac: _defaults.hsnSac.text.trim(),
      defaultServiceMode: _defaults.serviceMode.text.trim(),
      defaultLineTitle: _defaults.lineTitle.text.trim(),
      logoKey: _logoKey,
      signatureKey: _signatureKey,
    );
  }

  /// Drops whatever is in the form and re-reads the row. Used by the error
  /// state's retry, where there is nothing to lose.
  void _refetch() {
    setState(() {
      _hydrated = false;
      _showErrors = false;
      _saveError = null;
    });
    ref.invalidate(invoiceSettingsProvider);
  }

  Future<void> _confirmReload() async {
    final ok = await showConfirmDialog(
      context: context,
      title: 'Reload settings?',
      message:
          'Anything typed since the last save is discarded and the stored '
          'settings are read again.',
      confirmLabel: 'Discard & reload',
    );
    if (!ok || !mounted) return;
    _refetch();
  }

  Future<void> _save() async {
    if (_saving) return;
    final errors = _errors();
    final settings = _collect();
    if (errors.hasBlocking || !settings.hasSellerGstin) {
      setState(() {
        _showErrors = true;
        _saveError = errors.hasBlocking
            ? 'Please fix the highlighted fields and save again.'
            : 'A seller GSTIN is required. Its first two digits decide whether '
                  'an invoice carries CGST + SGST or IGST, so the server '
                  'refuses to issue one without it.';
      });
      return;
    }
    setState(() {
      _showErrors = true;
      _saving = true;
      _saveError = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    try {
      final saved = await ref
          .read(invoiceRepositoryProvider)
          .saveSettings(settings);
      if (!mounted) return;
      ref.invalidate(invoiceSettingsProvider);
      setState(() {
        // Re-read from the response so server normalisation (an uppercased
        // GSTIN, a trimmed line) is what the admin is looking at.
        _hydrate(saved);
        _saving = false;
        _showErrors = false;
      });
      messenger.showSnackBar(
        const SnackBar(
          content: Text(
            'Invoice settings saved — new invoices print this '
            'letterhead.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      // The backend names the offending KEY, never its value, so no bank detail
      // can reach the screen through here.
      setState(() {
        _saving = false;
        _saveError = friendlyErrorMessage(e);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = ref.watch(currentUserProvider);
    if (user == null || !user.canManageInvoiceSettings) {
      return const _AccessDenied();
    }

    final async = ref.watch(invoiceSettingsProvider);
    ref.listen<AsyncValue<InvoiceSettings?>>(invoiceSettingsProvider, (
      _,
      next,
    ) {
      if (_hydrated) return;
      if (next case AsyncData(:final value)) {
        setState(() {
          _hydrate(value);
          _hydrated = true;
        });
      }
    });

    // Field-level messages only appear once a save has been attempted; the
    // state/GSTIN warning is advisory and shows as soon as the pair disagrees.
    final errors = _showErrors
        ? _errors()
        : _FormErrors.warningsOnly(_stateWarning());

    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          AppTopbar(
            title: 'Invoice Settings',
            subtitle:
                'Letterhead, bank, declaration and defaults printed on '
                'every tax invoice',
            actions: [
              AppButton(
                label: 'Reload',
                icon: Icons.refresh_rounded,
                kind: BtnKind.ghost,
                onPressed: _saving ? null : _confirmReload,
              ),
              AppButton(
                label: 'Save settings',
                icon: Icons.save_outlined,
                loading: _saving,
                onPressed: _hydrated && !_saving ? _save : null,
              ),
            ],
          ),
          Expanded(
            child: _hydrated
                ? _EditorBody(
                    company: _company,
                    bank: _bank,
                    footer: _footer,
                    defaults: _defaults,
                    declaration: _declaration,
                    errors: errors,
                    configured: _configured,
                    logoKey: _logoKey,
                    signatureKey: _signatureKey,
                    saveError: _saveError,
                    saving: _saving,
                    onChanged: () => setState(() {}),
                    onAddDeclaration: () => setState(
                      () => _declaration.add(TextEditingController()),
                    ),
                    onRemoveDeclaration: (i) =>
                        setState(() => _declaration.removeAt(i).dispose()),
                    onSave: _save,
                  )
                : switch (async) {
                    AsyncError(:final error) => _LoadError(
                      message: friendlyErrorMessage(error),
                      onRetry: _refetch,
                    ),
                    _ => const _LoadingBody(),
                  },
          ),
        ],
      ),
    );
  }
}

/// Validation messages for one pass over the form. [stateWarning] is advisory —
/// everything else blocks the save, because the server would 400 on it anyway.
class _FormErrors {
  const _FormErrors({
    this.companyGstin,
    this.sellerGstin,
    this.email,
    this.address,
    this.gstRate,
    this.stateWarning,
  });

  const _FormErrors.warningsOnly(this.stateWarning)
    : companyGstin = null,
      sellerGstin = null,
      email = null,
      address = null,
      gstRate = null;

  final String? companyGstin;
  final String? sellerGstin;
  final String? email;
  final String? address;
  final String? gstRate;
  final String? stateWarning;

  bool get hasBlocking =>
      companyGstin != null ||
      sellerGstin != null ||
      email != null ||
      address != null ||
      gstRate != null;
}

class _CompanyFields {
  final name = TextEditingController();
  final address = TextEditingController();
  final gstin = TextEditingController();
  final state = TextEditingController();
  final email = TextEditingController();
  final website = TextEditingController();
  final signFor = TextEditingController();

  List<TextEditingController> get all => [
    name,
    address,
    gstin,
    state,
    email,
    website,
    signFor,
  ];
}

class _BankFields {
  final name = TextEditingController();
  final accountNo = TextEditingController();
  final branchIfsc = TextEditingController();

  List<TextEditingController> get all => [name, accountNo, branchIfsc];
}

class _FooterFields {
  final jurisdiction = TextEditingController();
  final computerGenerated = TextEditingController();

  List<TextEditingController> get all => [jurisdiction, computerGenerated];
}

class _DefaultFields {
  final sellerGstin = TextEditingController();
  final gstRate = TextEditingController();
  final hsnSac = TextEditingController();
  final serviceMode = TextEditingController();
  final lineTitle = TextEditingController();

  List<TextEditingController> get all => [
    sellerGstin,
    gstRate,
    hsnSac,
    serviceMode,
    lineTitle,
  ];
}

class _EditorBody extends StatelessWidget {
  const _EditorBody({
    required this.company,
    required this.bank,
    required this.footer,
    required this.defaults,
    required this.declaration,
    required this.errors,
    required this.configured,
    required this.logoKey,
    required this.signatureKey,
    required this.saveError,
    required this.saving,
    required this.onChanged,
    required this.onAddDeclaration,
    required this.onRemoveDeclaration,
    required this.onSave,
  });

  final _CompanyFields company;
  final _BankFields bank;
  final _FooterFields footer;
  final _DefaultFields defaults;
  final List<TextEditingController> declaration;
  final _FormErrors errors;
  final bool configured;
  final String logoKey;
  final String signatureKey;
  final String? saveError;
  final bool saving;
  final VoidCallback onChanged;
  final VoidCallback onAddDeclaration;
  final ValueChanged<int> onRemoveDeclaration;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return SingleChildScrollView(
      padding: EdgeInsets.all(mobile ? 16 : 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const _PrerequisiteNote(),
              if (!configured) const _NotConfiguredNote(),
              if (errors.stateWarning != null)
                _NoticeCard(
                  icon: Icons.warning_amber_rounded,
                  tint: AppColors.warn,
                  title: 'Check the seller state',
                  message: errors.stateWarning ?? '',
                ),
              if (saveError != null)
                _NoticeCard(
                  icon: Icons.error_outline_rounded,
                  tint: AppColors.danger,
                  title: 'Could not save',
                  message: saveError ?? '',
                ),
              _CompanySection(
                fields: company,
                gstinError: errors.companyGstin,
                emailError: errors.email,
                addressError: errors.address,
                onChanged: onChanged,
              ),
              _BankSection(fields: bank),
              _DeclarationSection(
                items: declaration,
                onAdd: onAddDeclaration,
                onRemove: onRemoveDeclaration,
              ),
              _FooterSection(fields: footer),
              _DefaultsSection(
                fields: defaults,
                gstinError: errors.sellerGstin,
                rateError: errors.gstRate,
                onChanged: onChanged,
              ),
              _LetterheadImagesSection(
                logoKey: logoKey,
                signatureKey: signatureKey,
              ),
              Align(
                alignment: Alignment.centerRight,
                child: AppButton(
                  label: 'Save settings',
                  icon: Icons.save_outlined,
                  loading: saving,
                  onPressed: saving ? null : onSave,
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _CompanySection extends StatelessWidget {
  const _CompanySection({
    required this.fields,
    required this.gstinError,
    required this.emailError,
    required this.addressError,
    required this.onChanged,
  });

  final _CompanyFields fields;
  final String? gstinError;
  final String? emailError;
  final String? addressError;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.business_outlined,
      title: 'Company',
      note: 'The letterhead block at the top of every invoice.',
      children: [
        _Field(
          label: 'Company name',
          controller: fields.name,
          hint: 'Vistar Logitek Pvt. Ltd.',
          maxLength: 200,
        ),
        _Field(
          label: 'Address',
          controller: fields.address,
          hint: 'One line per row — street, area, city – PIN',
          helper: 'Up to 10 lines; blank lines are dropped.',
          maxLines: 5,
          errorText: addressError,
          onChanged: onChanged,
        ),
        _Field(
          label: 'GSTIN',
          controller: fields.gstin,
          hint: '27ABCDE1234F1Z5',
          helper: 'Used as the seller GSTIN unless one is set under Defaults.',
          maxLength: 15,
          capitalise: true,
          errorText: gstinError,
          onChanged: onChanged,
        ),
        _Field(
          label: 'State',
          controller: fields.state,
          hint: 'Maharashtra',
          maxLength: 80,
          onChanged: onChanged,
        ),
        _Field(
          label: 'Email',
          controller: fields.email,
          hint: 'accounts@vistarlogitek.com',
          maxLength: 200,
          keyboardType: TextInputType.emailAddress,
          errorText: emailError,
          onChanged: onChanged,
        ),
        _Field(
          label: 'Website',
          controller: fields.website,
          hint: 'www.vistarlogitek.com',
          maxLength: 200,
        ),
        _Field(
          label: 'Signature caption',
          controller: fields.signFor,
          hint: 'For Vistar Logitek Pvt. Ltd.',
          helper: 'Printed above the authorised signatory line.',
          maxLength: 200,
          last: true,
        ),
      ],
    );
  }
}

class _BankSection extends StatelessWidget {
  const _BankSection({required this.fields});

  final _BankFields fields;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.account_balance_outlined,
      title: "Company's bank details",
      note:
          'Printed in the bank block. This is where customers pay, so only '
          'an admin may change it.',
      children: [
        _Field(
          label: 'Bank name',
          controller: fields.name,
          hint: 'Bank the account is held with',
          maxLength: 200,
        ),
        _Field(
          label: 'Account number',
          controller: fields.accountNo,
          hint: 'Account number as printed on the cheque',
          maxLength: 40,
        ),
        _Field(
          label: 'Branch & IFSC',
          controller: fields.branchIfsc,
          hint: 'Branch name & IFSC',
          maxLength: 120,
          last: true,
        ),
      ],
    );
  }
}

class _DeclarationSection extends StatelessWidget {
  const _DeclarationSection({
    required this.items,
    required this.onAdd,
    required this.onRemove,
  });

  final List<TextEditingController> items;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.rule_folder_outlined,
      title: 'Declaration',
      note:
          'Numbered automatically unless a paragraph already begins with its '
          'own number. Up to 10 paragraphs; empty ones are dropped on save.',
      children: [
        for (var i = 0; i < items.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: TextField(
                    key: ValueKey(items[i]),
                    controller: items[i],
                    minLines: 2,
                    maxLines: 4,
                    inputFormatters: [LengthLimitingTextInputFormatter(2000)],
                    decoration: InputDecoration(
                      hintText: i == 0
                          ? 'GST payable under Forward Charge.'
                          : 'We declare that this invoice shows the actual '
                                'price of the services described.',
                      prefixText: '${i + 1}.  ',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton(
                  tooltip: 'Remove paragraph ${i + 1}',
                  icon: const Icon(Icons.delete_outline_rounded),
                  color: AppColors.slate,
                  onPressed: items.length == 1 ? null : () => onRemove(i),
                ),
              ],
            ),
          ),
        Align(
          alignment: Alignment.centerLeft,
          child: AppButton(
            label: 'Add paragraph',
            icon: Icons.add_rounded,
            kind: BtnKind.ghost,
            small: true,
            onPressed: items.length >= 10 ? null : onAdd,
          ),
        ),
      ],
    );
  }
}

class _FooterSection extends StatelessWidget {
  const _FooterSection({required this.fields});

  final _FooterFields fields;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.horizontal_rule_rounded,
      title: 'Footer',
      note: 'Centred under the rule at the bottom of every page.',
      children: [
        _Field(
          label: 'Jurisdiction line',
          controller: fields.jurisdiction,
          hint: 'Subject to Pune Jurisdiction',
          maxLength: 200,
        ),
        _Field(
          label: 'Computer-generated line',
          controller: fields.computerGenerated,
          hint: 'This is a Computer Generated Invoice',
          maxLength: 200,
          last: true,
        ),
      ],
    );
  }
}

class _DefaultsSection extends StatelessWidget {
  const _DefaultsSection({
    required this.fields,
    required this.gstinError,
    required this.rateError,
    required this.onChanged,
  });

  final _DefaultFields fields;
  final String? gstinError;
  final String? rateError;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.tune_rounded,
      title: 'Tax & line defaults',
      note:
          'What the create screen seeds an invoice with. Anything typed on '
          'the invoice itself overrides these.',
      children: [
        _Field(
          label: 'Seller GSTIN',
          controller: fields.sellerGstin,
          hint: 'Leave blank to use the company GSTIN above',
          helper:
              'Its first two digits decide CGST + SGST vs IGST. Without '
              'one — here or above — no invoice can be issued.',
          maxLength: 15,
          capitalise: true,
          errorText: gstinError,
          onChanged: onChanged,
        ),
        _Field(
          label: 'GST rate %',
          controller: fields.gstRate,
          hint: '18',
          helper: 'Blank falls back to the statutory 18% on freight.',
          maxLength: 6,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          errorText: rateError,
          onChanged: onChanged,
        ),
        _Field(
          label: 'Default HSN / SAC',
          controller: fields.hsnSac,
          hint: '996511',
          maxLength: 16,
        ),
        _Field(
          label: 'Default service mode',
          controller: fields.serviceMode,
          hint: 'Express',
          maxLength: 40,
        ),
        _Field(
          label: 'Default line title',
          controller: fields.lineTitle,
          hint: 'Freight Charge-',
          maxLength: 200,
          last: true,
        ),
      ],
    );
  }
}

class _LetterheadImagesSection extends StatelessWidget {
  const _LetterheadImagesSection({
    required this.logoKey,
    required this.signatureKey,
  });

  final String logoKey;
  final String signatureKey;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      icon: Icons.image_outlined,
      title: 'Logo & signature',
      note:
          'Storage keys, not links — the renderer loads the bytes on the '
          'server. There is no upload endpoint on this module, so the images '
          'are managed server-side; these keys are shown for reference and are '
          'saved back unchanged.',
      children: [
        _ReadOnlyKey(label: 'Logo key', value: logoKey),
        _ReadOnlyKey(label: 'Signature key', value: signatureKey, last: true),
      ],
    );
  }
}

class _ReadOnlyKey extends StatelessWidget {
  const _ReadOnlyKey({
    required this.label,
    required this.value,
    this.last = false,
  });

  final String label;
  final String value;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: LabeledField(
        label: label,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.mist,
            border: Border.all(color: AppColors.line),
            borderRadius: BorderRadius.circular(10),
          ),
          child: SelectableText(
            value.isEmpty ? 'Not set' : value,
            style: TextStyle(
              fontSize: 13,
              color: value.isEmpty ? AppColors.slate : AppColors.ink,
            ),
          ),
        ),
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.controller,
    this.hint = '',
    this.helper = '',
    this.maxLines = 1,
    this.maxLength,
    this.errorText,
    this.keyboardType,
    this.capitalise = false,
    this.onChanged,
    this.last = false,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final String helper;
  final int maxLines;
  final int? maxLength;
  final String? errorText;
  final TextInputType? keyboardType;

  /// GSTINs are stored uppercase by the server; typing them lowercase and
  /// watching the validation fail would be a needless trap.
  final bool capitalise;
  final VoidCallback? onChanged;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final limit = maxLength;
    final notify = onChanged;
    return Padding(
      padding: EdgeInsets.only(bottom: last ? 0 : 14),
      child: LabeledField(
        label: label,
        errorText: errorText,
        child: TextField(
          controller: controller,
          maxLines: maxLines,
          minLines: maxLines > 1 ? maxLines : null,
          keyboardType: keyboardType,
          textCapitalization: capitalise
              ? TextCapitalization.characters
              : TextCapitalization.none,
          inputFormatters: [
            if (limit != null) LengthLimitingTextInputFormatter(limit),
            if (capitalise) _UpperCaseFormatter(),
          ],
          decoration: InputDecoration(
            hintText: hint.isEmpty ? null : hint,
            helperText: helper.isEmpty ? null : helper,
            helperMaxLines: 3,
          ),
          onChanged: notify == null ? null : (_) => notify(),
        ),
      ),
    );
  }
}

/// Keeps a GSTIN in the case the server stores it in, without moving the caret.
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) => TextEditingValue(
    text: newValue.text.toUpperCase(),
    selection: newValue.selection,
    composing: TextRange.empty,
  );
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.icon,
    required this.title,
    required this.children,
    this.note = '',
  });

  final IconData icon;
  final String title;
  final String note;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SectionTitle(icon: icon, title: title),
            if (note.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: Text(
                  note,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.slate,
                  ),
                ),
              ),
            ...children,
          ],
        ),
      ),
    );
  }
}

class _PrerequisiteNote extends StatelessWidget {
  const _PrerequisiteNote();

  @override
  Widget build(BuildContext context) {
    return const _NoticeCard(
      icon: Icons.receipt_long_outlined,
      tint: AppColors.plum,
      title: 'Invoicing needs this page',
      message:
          'Every invoice PDF is rendered from this one record — the '
          'letterhead, the bank block, the declaration and, above all, the '
          'seller GSTIN. No invoice can be issued until it is saved. A '
          'half-filled record prints a thinner document, never a broken one.',
    );
  }
}

class _NotConfiguredNote extends StatelessWidget {
  const _NotConfiguredNote();

  @override
  Widget build(BuildContext context) {
    return const _NoticeCard(
      icon: Icons.edit_note_rounded,
      tint: AppColors.warn,
      title: 'Not configured yet',
      message:
          'Nothing has been saved for this company. The grey text in each '
          'field is an example, not a value — fill in what applies and press '
          'Save settings.',
    );
  }
}

class _NoticeCard extends StatelessWidget {
  const _NoticeCard({
    required this.icon,
    required this.tint,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final Color tint;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: AppCard(
        color: tint.withValues(alpha: 0.06),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: tint),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w800,
                      color: AppColors.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    message,
                    style: const TextStyle(
                      fontSize: 12.5,
                      height: 1.45,
                      color: AppColors.slate,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _LoadingBody extends StatelessWidget {
  const _LoadingBody();

  @override
  Widget build(BuildContext context) {
    final mobile = MediaQuery.sizeOf(context).width < 600;
    return SingleChildScrollView(
      padding: EdgeInsets.all(mobile ? 16 : 28),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 900),
          child: const ShimmerCards(cards: 4, height: 168),
        ),
      ),
    );
  }
}

class _LoadError extends StatelessWidget {
  const _LoadError({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: AppCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.cloud_off_rounded,
                  size: 40,
                  color: AppColors.slate,
                ),
                const SizedBox(height: 12),
                const Text(
                  'Could not load the invoice settings',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: AppColors.ink,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: AppColors.slate,
                  ),
                ),
                const SizedBox(height: 16),
                AppButton(
                  label: 'Try again',
                  icon: Icons.refresh_rounded,
                  kind: BtnKind.ghost,
                  onPressed: onRetry,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _AccessDenied extends StatelessWidget {
  const _AccessDenied();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.mist,
      body: Column(
        children: [
          const AppTopbar(title: 'Invoice Settings'),
          Expanded(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: const [
                    Icon(
                      Icons.lock_outline_rounded,
                      size: 48,
                      color: AppColors.slate,
                    ),
                    SizedBox(height: 12),
                    Text(
                      'Only an admin can change the invoice letterhead.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: AppColors.slate),
                    ),
                    SizedBox(height: 6),
                    Text(
                      'It holds the bank account customers pay into.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, color: AppColors.slate),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
