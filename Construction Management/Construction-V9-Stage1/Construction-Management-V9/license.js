
/* =====================================================
   V9 - Independent Licensing Client
   Server-side enforcement: Supabase SQL
   ===================================================== */

(function () {
  'use strict';

  const state = {
    ready: false,
    isOwner: false,
    status: 'unknown',
    expiresAt: null,
    remainingDays: null,
    error: null,
    loading: false
  };

  const $ = (selector) => document.querySelector(selector);

  const esc = (value) =>
    String(value ?? '').replace(/[&<>"']/g, (char) => ({
      '&': '&amp;',
      '<': '&lt;',
      '>': '&gt;',
      '"': '&quot;',
      "'": '&#39;'
    })[char]);

  function getClient() {
    if (!window.sb || typeof window.sb.rpc !== 'function') {
      throw new Error('اتصال Supabase غير جاهز.');
    }
    return window.sb;
  }

  function canWrite() {
    if (!state.ready) return false;
    if (state.isOwner) return true;

    if (!state.expiresAt) return false;

    return new Date(state.expiresAt).getTime() > Date.now();
  }

  function label() {
    if (state.loading) return 'جارٍ التحقق من الترخيص...';

    if (!state.ready) return 'الترخيص غير متحقق';

    if (state.isOwner) return 'ترخيص المالك';

    if (!canWrite()) return 'انتهت مدة الترخيص';

    if (state.status === 'trial') {
      return `تجربة مجانية — ${state.remainingDays ?? 0} يوم`;
    }

    return `ترخيص نشط — ${state.remainingDays ?? 0} يوم`;
  }

  async function init() {
    state.loading = true;
    state.ready = false;
    state.error = null;
    renderBadge();

    try {
      const client = getClient();

      const { data, error } = await client.rpc('ensure_app_license');

      if (error) throw error;

      const result = Array.isArray(data) ? data[0] : data;

      if (!result || typeof result !== 'object') {
        throw new Error('استجابة الترخيص غير صحيحة.');
      }

      state.isOwner = result.is_owner === true;
      state.status = result.status || 'unknown';
      state.expiresAt = result.expires_at || null;
      state.remainingDays = result.remaining_days ?? null;
      state.ready = true;
      state.error = null;

      renderBadge();
      return state;

    } catch (error) {
      state.ready = false;
      state.isOwner = false;
      state.status = 'unknown';
      state.expiresAt = null;
      state.remainingDays = null;
      state.error = error.message || 'تعذر التحقق من الترخيص.';

      renderBadge();

      console.error('License initialization error:', error);

      return state;

    } finally {
      state.loading = false;
      renderBadge();
    }
  }

  function renderBadge() {
    let element = $('#licenseStatus');

    if (!element) {
      const header = document.querySelector('header');
      if (!header) return;

      element = document.createElement('div');
      element.id = 'licenseStatus';
      element.className = 'license-status';
      header.appendChild(element);
    }

    element.textContent = label();

    element.title = state.error
      ? state.error
      : state.expiresAt
        ? `تاريخ الانتهاء: ${new Date(state.expiresAt).toLocaleString('ar-EG')}`
        : '';

    element.classList.toggle(
      'expired',
      state.ready && !canWrite()
    );
  }

  function addPanelButton() {
    if ($('#licenseOpenButton')) return;

    const header = document.querySelector('header');
    if (!header) return;

    const button = document.createElement('button');

    button.id = 'licenseOpenButton';
    button.type = 'button';
    button.className = 'license-open-button';
    button.textContent = 'إدارة الترخيص';

    button.addEventListener('click', panel);

    header.appendChild(button);
  }

  async function redeem() {
    const input = $('#licenseCode');
    const code = input?.value.trim();

    if (!code) {
      alert('اكتب كود التفعيل أولًا.');
      return;
    }

    if (!state.ready || state.isOwner) {
      alert('لا يمكن تنفيذ عملية التفعيل في الحالة الحالية.');
      return;
    }

    const button = $('#licenseRedeemButton');

    if (button) button.disabled = true;

    try {
      const client = getClient();

      const { data, error } = await client.rpc(
        'redeem_app_license_code',
        { p_code: code }
      );

      if (error) throw error;

      await init();

      if (!state.ready || !canWrite()) {
        throw new Error('لم يتم تأكيد تفعيل الترخيص.');
      }

      alert(
        `تم التفعيل بنجاح لمدة ${data?.duration_days ?? ''} يومًا.`
      );

      close();

    } catch (error) {
      alert('تعذر تفعيل الكود: ' + (error.message || 'خطأ غير معروف'));

    } finally {
      if (button) button.disabled = false;
    }
  }

  async function createCodes(days) {
    if (!state.ready || !state.isOwner) {
      alert('هذه العملية متاحة لمالك التطبيق فقط.');
      return;
    }

    const quantity = Number($('#licenseQty')?.value || 1);

    if (!Number.isInteger(quantity) || quantity < 1 || quantity > 50) {
      alert('عدد الأكواد يجب أن يكون من 1 إلى 50.');
      return;
    }

    if (![30, 90, 180, 365].includes(days)) {
      alert('مدة الترخيص غير صحيحة.');
      return;
    }

    // فتح نافذة الطباعة مباشرة من نقرة المستخدم لتجنب حظر النوافذ.
    const printWindow = window.open('', '_blank');

    if (!printWindow) {
      alert('اسمح بفتح النوافذ المنبثقة حتى تتمكن من طباعة الأكواد.');
      return;
    }

    printWindow.document.write(
      '<html dir="rtl"><head><meta charset="utf-8"><title>جاري إصدار الأكواد</title></head><body>جارٍ إصدار الأكواد...</body></html>'
    );

    try {
      const client = getClient();

      const { data, error } = await client.rpc(
        'admin_create_app_license_codes',
        {
          p_duration_days: days,
          p_quantity: quantity
        }
      );

      if (error) throw error;

      const codes = data?.codes;

      if (!Array.isArray(codes) || codes.length === 0) {
        throw new Error('لم يتم استلام الأكواد من الخادم.');
      }

      const safeCodes = esc(codes.join('\n'));

      printWindow.document.open();
      printWindow.document.write(`
        <!DOCTYPE html>
        <html lang="ar" dir="rtl">
        <head>
          <meta charset="utf-8">
          <title>أكواد التفعيل</title>
          <style>
            body {
              font-family: Tahoma, Arial, sans-serif;
              padding: 25px;
              line-height: 2;
            }
            pre {
              white-space: pre-wrap;
              padding: 15px;
              border: 1px solid #ccc;
              border-radius: 8px;
              font-size: 17px;
            }
            button {
              padding: 10px 25px;
              cursor: pointer;
            }
            @media print {
              button { display: none; }
            }
          </style>
        </head>
        <body>
          <h2>أكواد تفعيل التطبيق</h2>
          <p>مدة الترخيص: ${days} يومًا</p>
          <p>عدد الأكواد: ${codes.length}</p>
          <pre>${safeCodes}</pre>
          <button onclick="window.print()">طباعة الأكواد</button>
        </body>
        </html>
      `);
      printWindow.document.close();

    } catch (error) {
      printWindow.close();

      alert(
        'تعذر إصدار الأكواد: ' +
        (error.message || 'خطأ غير معروف')
      );
    }
  }

  function panel() {
    let host = $('#licensePanel');

    if (!host) {
      host = document.createElement('div');
      host.id = 'licensePanel';
      host.className = 'license-overlay';
      document.body.appendChild(host);
    }

    const ownerContent = `
      <hr>
      <h3>إصدار أكواد جديدة</h3>

      <label for="licenseQty">عدد الأكواد (1 إلى 50)</label>

      <input
        id="licenseQty"
        type="number"
        min="1"
        max="50"
        value="1"
      >

      <div class="license-actions">
        <button type="button" onclick="CMSLicense.createCodes(30)">
          إصدار 30 يومًا
        </button>

        <button type="button" onclick="CMSLicense.createCodes(90)">
          إصدار 90 يومًا
        </button>

        <button type="button" onclick="CMSLicense.createCodes(180)">
          إصدار 180 يومًا
        </button>

        <button type="button" onclick="CMSLicense.createCodes(365)">
          إصدار 365 يومًا
        </button>
      </div>

      <p class="license-note">
        تظهر الأكواد مرة واحدة عند إصدارها. احتفظ بها في مكان آمن.
      </p>
    `;

    const customerContent = `
      <label for="licenseCode">كود التفعيل</label>

      <input
        id="licenseCode"
        autocomplete="off"
        placeholder="أدخل كود التفعيل"
      >

      <div class="license-actions">
        <button
          id="licenseRedeemButton"
          type="button"
          onclick="CMSLicense.redeem()"
        >
          تفعيل الكود
        </button>
      </div>
    `;

    host.innerHTML = `
      <section class="license-card" dir="rtl">

        <button
          class="license-close"
          type="button"
          onclick="CMSLicense.close()"
          aria-label="إغلاق"
        >×</button>

        <h2>إدارة الترخيص والتفعيل</h2>

        <p class="license-state">${esc(label())}</p>

        ${
          state.error
            ? `<p class="license-note">${esc(state.error)}</p>`
            : ''
        }

        ${
          state.expiresAt
            ? `<p>تاريخ الانتهاء:
                <b>${esc(new Date(state.expiresAt).toLocaleString('ar-EG'))}</b>
              </p>`
            : ''
        }

        ${
          !state.ready
            ? '<p>يجب تسجيل الدخول والتحقق من الترخيص أولًا.</p>'
            : state.isOwner
              ? ownerContent
              : customerContent
        }

        <div class="license-actions">
          <button
            class="secondary"
            type="button"
            onclick="CMSLicense.close()"
          >إغلاق</button>
        </div>

      </section>
    `;

    host.classList.add('show');
  }

  function close() {
    $('#licensePanel')?.classList.remove('show');
  }

  // منع إغلاق اللوحة عند الضغط داخل البطاقة.
  document.addEventListener('click', (event) => {
    const overlay = $('#licensePanel');

    if (overlay && event.target === overlay) {
      close();
    }
  });

  window.CMSLicense = {
    state,
    init,
    canWrite,
    renderBadge,
    addPanelButton,
    panel,
    close,
    redeem,
    createCodes
  };

})();
