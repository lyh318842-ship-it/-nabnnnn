import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

class StaticInfoPage extends StatefulWidget {
  final String title;
  final IconData icon;
  final List<String> paragraphs;
  final List<Widget> actions;

  const StaticInfoPage({
    super.key,
    required this.title,
    required this.icon,
    required this.paragraphs,
    this.actions = const [],
  });

  @override
  State<StaticInfoPage> createState() => _StaticInfoPageState();
}

class _StaticInfoPageState extends State<StaticInfoPage> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final _InfoPageContent _content;

  @override
  void initState() {
    super.initState();
    _content = _InfoPageContent.from(widget.title, widget.paragraphs, widget.icon);
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title), centerTitle: true),
      body: SafeArea(
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            SliverToBoxAdapter(child: _AnimatedEntrance(controller: _controller, index: 0, child: _HeroHeader(content: _content))),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(18, 20, 18, 34),
              sliver: SliverList.separated(
                itemCount: _content.sections.length + (widget.actions.isEmpty ? 0 : 1),
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (context, index) {
                  if (index == _content.sections.length) {
                    return _AnimatedEntrance(
                      controller: _controller,
                      index: index + 1,
                      child: _ActionPanel(actions: widget.actions),
                    );
                  }
                  return _AnimatedEntrance(
                    controller: _controller,
                    index: index + 1,
                    child: _InfoSectionCard(section: _content.sections[index]),
                  );
                },
              ),
            ),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 0, 18, 26),
                child: Text(
                  'نلتزم بتقديم تجربة صحية رقمية موثوقة، آمنة، وسهلة الاستخدام مع احترام خصوصيتك واحتياجاتك الصحية.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant, height: 1.55),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HeroHeader extends StatelessWidget {
  const _HeroHeader({required this.content});

  final _InfoPageContent content;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 12, 18, 0),
      padding: const EdgeInsets.fromLTRB(22, 26, 22, 24),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(34),
        gradient: LinearGradient(
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
          colors: [scheme.primary, scheme.secondary, scheme.tertiaryContainer],
        ),
        boxShadow: [BoxShadow(color: scheme.primary.withOpacity(.24), blurRadius: 30, offset: const Offset(0, 16))],
      ),
      child: Stack(
        children: [
          PositionedDirectional(end: -18, top: -22, child: _GlowCircle(size: 112, color: scheme.onPrimary.withOpacity(.16))),
          PositionedDirectional(start: -26, bottom: -34, child: _GlowCircle(size: 92, color: scheme.onPrimary.withOpacity(.12))),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(color: scheme.onPrimary.withOpacity(.16), borderRadius: BorderRadius.circular(24), border: Border.all(color: scheme.onPrimary.withOpacity(.22))),
                child: Icon(content.icon, color: scheme.onPrimary, size: 38),
              ),
              const SizedBox(height: 18),
              Text(content.title, style: Theme.of(context).textTheme.headlineMedium?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w900, height: 1.15)),
              const SizedBox(height: 10),
              Text(content.subtitle, style: Theme.of(context).textTheme.bodyLarge?.copyWith(color: scheme.onPrimary.withOpacity(.92), height: 1.6)),
              const SizedBox(height: 18),
              Wrap(spacing: 8, runSpacing: 8, children: content.tags.map((tag) => _HeaderChip(label: tag)).toList()),
            ],
          ),
        ],
      ),
    );
  }
}

class _GlowCircle extends StatelessWidget {
  const _GlowCircle({required this.size, required this.color});
  final double size;
  final Color color;
  @override
  Widget build(BuildContext context) => Container(width: size, height: size, decoration: BoxDecoration(shape: BoxShape.circle, color: color));
}

class _HeaderChip extends StatelessWidget {
  const _HeaderChip({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: scheme.onPrimary.withOpacity(.14), borderRadius: BorderRadius.circular(100), border: Border.all(color: scheme.onPrimary.withOpacity(.18))),
      child: Text(label, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: scheme.onPrimary, fontWeight: FontWeight.w700)),
    );
  }
}

class _InfoSectionCard extends StatelessWidget {
  const _InfoSectionCard({required this.section});
  final _InfoSection section;
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.surface.withOpacity(Theme.of(context).brightness == Brightness.dark ? .42 : .72),
        borderRadius: BorderRadius.circular(26),
        border: Border.all(color: scheme.outlineVariant.withOpacity(.55)),
        boxShadow: [BoxShadow(color: scheme.shadow.withOpacity(.06), blurRadius: 24, offset: const Offset(0, 12))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(padding: const EdgeInsets.all(10), decoration: BoxDecoration(color: scheme.primaryContainer, borderRadius: BorderRadius.circular(16)), child: Icon(section.icon, color: scheme.onPrimaryContainer, size: 22)),
          const SizedBox(width: 12),
          Expanded(child: Text(section.title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w900))),
        ]),
        const SizedBox(height: 12),
        Text(section.body, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.75, color: scheme.onSurfaceVariant)),
        if (section.points.isNotEmpty) ...[
          const SizedBox(height: 12),
          ...section.points.map((point) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(Icons.check_circle_rounded, color: scheme.primary, size: 18),
                  const SizedBox(width: 8),
                  Expanded(child: Text(point, style: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45))),
                ]),
              )),
        ],
      ]),
    );
  }
}

class _ActionPanel extends StatelessWidget {
  const _ActionPanel({required this.actions});
  final List<Widget> actions;
  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: actions.map((action) => Padding(padding: const EdgeInsets.only(bottom: 10), child: action)).toList());
}

class _AnimatedEntrance extends StatelessWidget {
  const _AnimatedEntrance({required this.controller, required this.index, required this.child});
  final AnimationController controller;
  final int index;
  final Widget child;
  @override
  Widget build(BuildContext context) {
    final start = math.min(index * .08, .62);
    final animation = CurvedAnimation(parent: controller, curve: Interval(start, 1, curve: Curves.easeOutCubic));
    return FadeTransition(opacity: animation, child: SlideTransition(position: Tween<Offset>(begin: const Offset(0, .08), end: Offset.zero).animate(animation), child: child));
  }
}

class _InfoPageContent {
  const _InfoPageContent({required this.title, required this.subtitle, required this.icon, required this.tags, required this.sections});
  final String title;
  final String subtitle;
  final IconData icon;
  final List<String> tags;
  final List<_InfoSection> sections;

  factory _InfoPageContent.from(String title, List<String> fallback, IconData icon) {
    switch (title) {
      case 'عن التطبيق':
        return _InfoPageContent(title: title, subtitle: 'منصة صحية متكاملة تجمع خدمات الرعاية الرقمية في مكان واحد، وتساعدك على إدارة رحلتك الصحية بثقة ووضوح.', icon: icon, tags: const ['حجز', 'استشارات', 'ذكاء اصطناعي', 'سجل صحي'], sections: const [
          _InfoSection(Icons.favorite_rounded, 'رعاية صحية شاملة', 'يوفر تطبيق نبض تجربة صحية متكاملة تبدأ من البحث عن الطبيب أو التخصص المناسب، مروراً بحجز المواعيد الطبية وإدارة تفاصيلها، وصولاً إلى الاستشارات الطبية والمحادثات الفردية بين المريض والطبيب ضمن بيئة رقمية سهلة ومنظمة.', ['البحث عن الأطباء والتخصصات.', 'حجز المواعيد ومتابعة حالتها.', 'الخرائط والمواقع الطبية للوصول الأسرع.']),
          _InfoSection(Icons.forum_rounded, 'تواصل طبي آمن', 'يدعم التطبيق المحادثات الفردية والجماعية الطبية لتسهيل المتابعة وتبادل المعلومات المهمة، مع تنظيم الرسائل والتنبيهات بطريقة تساعد المستخدم على عدم تفويت أي تحديث صحي أو موعد أو تذكير مهم.', ['محادثات فردية بين المريض والطبيب.', 'محادثات جماعية طبية عند الحاجة.', 'نظام إشعارات متقدم ومناسب للسياق.']),
          _InfoSection(Icons.auto_awesome_rounded, 'ذكاء اصطناعي صحي', 'يتيح مساعد نبض الصحي طرح الأسئلة الطبية العامة على الذكاء الاصطناعي، وتحليل السياق المقدم من المستخدم بشكل إرشادي يساعده على فهم الأعراض والخطوات التالية، مع التأكيد دائماً على أن الطبيب المختص هو المرجع الأساسي للحالات التشخيصية والعلاجية.', ['طرح أسئلة طبية منظمة.', 'إرشادات أولية آمنة.', 'تنبيه للحالات التي تستدعي مراجعة الطبيب أو الطوارئ.']),
          _InfoSection(Icons.health_and_safety_rounded, 'إدارة صحتك اليومية', 'يساعدك التطبيق على إدارة السجل الصحي والتذكيرات الطبية ومتابعة الأدوية بصورة أكثر وضوحاً، بحيث تصبح المعلومات الأساسية قريبة منك عند الحاجة وتدعم تجربة متابعة صحية مستمرة.', ['إدارة السجل الصحي.', 'التذكيرات الطبية.', 'متابعة الأدوية والالتزام بها.']),
          _InfoSection(Icons.security_rounded, 'خصوصية وموثوقية', 'صُمم نبض ليمنح المستخدم بيئة آمنة تحترم حساسية البيانات الصحية والشخصية، مع اعتماد صلاحيات وصول مناسبة وتخزين منظم للبيانات بما يحافظ على ثقة المرضى وتجربة استخدام مطمئنة.', ['حماية بيانات المرضى.', 'تنظيم الوصول للمعلومات.', 'تجربة حديثة متوافقة مع الوضع الليلي والفاتح.']),
        ]);
      case 'سياسة الخصوصية':
        return _InfoPageContent(title: title, subtitle: 'نوضح لك بشفافية كيف نتعامل مع بياناتك الشخصية والطبية ونحميها أثناء استخدام خدمات نبض.', icon: icon, tags: const ['خصوصية', 'تشفير', 'صلاحيات', 'حذف البيانات'], sections: const [
          _InfoSection(Icons.badge_rounded, 'البيانات الشخصية والطبية', 'نجمع البيانات اللازمة لتشغيل الخدمات مثل الحساب، المواعيد، الاستشارات، التذكيرات، السجل الصحي، والملفات الطبية التي يرفعها المستخدم. نتعامل مع البيانات الطبية باعتبارها معلومات حساسة لا تُستخدم إلا لتقديم الخدمة وتحسين تجربة الرعاية داخل التطبيق.', ['حماية بيانات الهوية والحساب.', 'حماية البيانات الطبية والأعراض والسجلات.', 'الاقتصار على البيانات الضرورية لتقديم الخدمة.']),
          _InfoSection(Icons.lock_rounded, 'التخزين والتشفير', 'نستخدم آليات تخزين آمنة وصلاحيات وصول مرتبطة بالحساب والخدمة المطلوبة. يتم التعامل مع المعلومات الحساسة بعناية، وتُطبّق طبقات حماية مناسبة لتقليل مخاطر الوصول غير المصرح به أو إساءة الاستخدام.', ['تخزين آمن للبيانات.', 'حماية المحادثات والملفات الطبية.', 'تقليل الوصول غير الضروري للمعلومات.']),
          _InfoSection(Icons.chat_bubble_rounded, 'خصوصية المحادثات والاستشارات', 'محتوى المحادثات والاستشارات الطبية يُستخدم لتقديم التواصل الطبي داخل التطبيق، ولا تتم مشاركته مع أطراف خارجية دون إذن المستخدم أو متطلب نظامي واضح. ننصح بعدم مشاركة معلومات غير ضرورية داخل قنوات الدعم العامة.', ['حماية المحادثات الفردية والجماعية.', 'خصوصية الاستشارات الطبية.', 'عدم مشاركة البيانات خارجياً بدون إذن.']),
          _InfoSection(Icons.photo_library_rounded, 'الصور والملفات الطبية', 'الصور والتحاليل والوصفات والملفات الطبية المرفوعة تُعامل كمحتوى حساس. يتم استخدامها فقط للغرض الذي رُفعت من أجله مثل عرضها للطبيب أو تحليلها ضمن الخدمة، مع الالتزام بحمايتها من الوصول غير المصرح.', ['أمن الصور والملفات الطبية.', 'استخدام الملفات ضمن سياق الخدمة فقط.', 'تجنب نشر المحتوى الطبي خارج التطبيق.']),
          _InfoSection(Icons.verified_user_rounded, 'حقوق المستخدم', 'يستطيع المستخدم طلب تحديث معلوماته أو حذف الحساب والبيانات وفق الإمكانات المتاحة والأنظمة المعمول بها. كما يحق له معرفة الغرض من استخدام البيانات وصلاحيات الوصول المرتبطة بها.', ['إمكانية طلب حذف الحساب والبيانات.', 'حق تحديث البيانات.', 'حق معرفة كيفية استخدام البيانات.']),
        ]);
      case 'شروط الاستخدام':
        return _InfoPageContent(title: title, subtitle: 'باستخدامك تطبيق نبض فإنك توافق على قواعد تهدف لحماية المستخدمين والأطباء وضمان تجربة صحية آمنة ومنظمة.', icon: icon, tags: const ['مسؤوليات', 'حجز', 'محادثات', 'AI'], sections: const [
          _InfoSection(Icons.person_rounded, 'مسؤوليات المستخدم', 'يلتزم المستخدم بتقديم معلومات صحيحة قدر الإمكان، وعدم إساءة استخدام خدمات الحجز أو المحادثات أو رفع محتوى مخالف أو مضلل. يجب استخدام التطبيق بطريقة قانونية ومحترمة تحفظ حقوق الآخرين وسلامة المجتمع الطبي.', ['تقديم معلومات دقيقة.', 'عدم إساءة استخدام الخدمات.', 'عدم رفع محتوى ضار أو مخالف.']),
          _InfoSection(Icons.medical_services_rounded, 'مسؤوليات الطبيب', 'يلتزم الطبيب باستخدام القنوات المخصصة داخل التطبيق للتواصل المهني، والرد وفق المتاح، والحفاظ على سرية معلومات المرضى، وتقديم الإرشاد الطبي ضمن حدود تخصصه ومسؤولياته المهنية.', ['احترام خصوصية المريض.', 'التواصل المهني داخل التطبيق.', 'تقديم إرشاد مناسب للتخصص.']),
          _InfoSection(Icons.smart_toy_rounded, 'شروط استخدام الذكاء الاصطناعي', 'المساعد الذكي يقدم معلومات صحية إرشادية ولا يُعد بديلاً كاملاً للطبيب أو الطوارئ أو التشخيص السريري. يجب مراجعة طبيب مختص عند استمرار الأعراض أو شدتها أو وجود علامات خطورة.', ['الذكاء الاصطناعي ليس بديلاً كاملاً للطبيب.', 'لا تعتمد عليه في الحالات الطارئة.', 'استخدمه لفهم عام وتنظيم الأسئلة.']),
          _InfoSection(Icons.event_available_rounded, 'الحجز والمحادثات', 'تخضع المواعيد لتوفر الطبيب أو العيادة، وقد تتغير أو تُلغى حسب الظروف. يجب استخدام المحادثات للغرض الصحي المناسب وعدم إرسال محتوى مزعج أو خارج السياق.', ['احترام مواعيد الحجز.', 'استخدام المحادثات لغرض طبي مناسب.', 'اتباع تعليمات الطبيب أو العيادة.']),
          _InfoSection(Icons.report_rounded, 'المخالفات والمحتوى المرفوع', 'قد يتم التعامل مع أي مخالفة عبر التحذير أو تقييد بعض الخدمات أو اتخاذ إجراء مناسب وفق سياسة التطبيق. يشمل ذلك المحتوى المسيء أو المزيف أو الذي ينتهك خصوصية الآخرين.', ['مراجعة البلاغات عند الحاجة.', 'تقييد الاستخدام عند المخالفات.', 'حماية المستخدمين من المحتوى الضار.']),
        ]);
      case 'الدعم الفني':
        return _InfoPageContent(title: title, subtitle: 'فريق الدعم هنا لمساعدتك في استخدام نبض وحل المشكلات التقنية أو مشكلات الحساب والخدمات بأسرع طريقة ممكنة.', icon: icon, tags: const ['تواصل', 'مواعيد دعم', 'استجابة', 'أسئلة شائعة'], sections: const [
          _InfoSection(Icons.contact_support_rounded, 'طرق التواصل', 'يمكنك التواصل مع الدعم عبر البريد الإلكتروني أو واتساب من الأزرار أدناه. عند إرسال طلبك، اذكر نوع المشكلة ورقم الهاتف أو البريد المرتبط بالحساب وخطوات حدوث المشكلة إن أمكن.', ['البريد الإلكتروني للدعم.', 'واتساب للمساعدة السريعة.', 'وصف واضح للمشكلة يسرّع الحل.']),
          _InfoSection(Icons.schedule_rounded, 'أوقات الدعم والاستجابة', 'يعمل الدعم على استقبال الطلبات ومراجعتها بحسب الأولوية. غالباً يتم الرد على المشكلات العامة خلال أقرب وقت متاح، بينما تُعطى مشكلات الدخول أو المواعيد أو الحالات العاجلة داخل التطبيق أولوية أعلى.', ['متابعة الطلبات حسب الأولوية.', 'توضيح معلومات الحساب يختصر وقت الاستجابة.', 'قد تختلف مدة الرد بحسب ضغط الطلبات.']),
          _InfoSection(Icons.build_circle_rounded, 'المشكلات التي نساعدك بها', 'يساعدك الفريق في مشكلات تسجيل الدخول، الحساب، المواعيد، الإشعارات، المحادثات، رفع الملفات، ظهور البيانات، أو أي خلل يمنعك من استخدام التطبيق بصورة طبيعية.', ['مشكلات الحساب والدخول.', 'مشكلات الحجز والإشعارات.', 'مشكلات المحادثات والملفات.']),
          _InfoSection(Icons.quiz_rounded, 'الأسئلة الشائعة', 'إذا لم تصلك الإشعارات فتحقق من صلاحيات الإشعارات في الجهاز. إذا تعذر رفع صورة فتأكد من صلاحية الصور والاتصال. إذا ظهرت مشكلة في الحجز فراجع حالة الموعد أو تواصل معنا بصورة توضح المشكلة.', ['لم تصل الإشعارات؟ تحقق من صلاحيات الجهاز.', 'تعذر رفع ملف؟ تحقق من الاتصال والصلاحيات.', 'مشكلة في موعد؟ أرسل تفاصيل الحجز للدعم.']),
        ]);
      default:
        return _InfoPageContent(title: title, subtitle: fallback.isNotEmpty ? fallback.first : 'معلومات مهمة لاستخدام التطبيق بثقة.', icon: icon, tags: const ['نبض', 'صحة', 'أمان'], sections: fallback.map((p) => _InfoSection(Icons.info_rounded, 'معلومة', p, const [])).toList());
    }
  }
}

class _InfoSection {
  const _InfoSection(this.icon, this.title, this.body, this.points);
  final IconData icon;
  final String title;
  final String body;
  final List<String> points;
}

class SupportPage extends StatelessWidget {
  const SupportPage({super.key});

  Future<void> _open(Uri uri) async => launchUrl(uri, mode: LaunchMode.externalApplication);

  @override
  Widget build(BuildContext context) => StaticInfoPage(
        title: 'الدعم الفني',
        icon: Icons.support_agent_rounded,
        paragraphs: const [],
        actions: [
          FilledButton.icon(onPressed: () => _open(Uri.parse('mailto:support@digl.com?subject=دعم تطبيق نبض')), icon: const Icon(Icons.email), label: const Text('التواصل عبر البريد الإلكتروني')),
          OutlinedButton.icon(onPressed: () => _open(Uri.parse('https://wa.me/781268449')), icon: const Icon(Icons.chat), label: const Text('التواصل عبر واتساب')),
        ],
      );
}

class PrivacyPolicyPage extends StatelessWidget {
  const PrivacyPolicyPage({super.key});
  @override
  Widget build(BuildContext context) => const StaticInfoPage(title: 'سياسة الخصوصية', icon: Icons.privacy_tip_rounded, paragraphs: []);
}

class TermsOfUsePage extends StatelessWidget {
  const TermsOfUsePage({super.key});
  @override
  Widget build(BuildContext context) => const StaticInfoPage(title: 'شروط الاستخدام', icon: Icons.gavel_rounded, paragraphs: []);
}

class AboutAppPage extends StatelessWidget {
  const AboutAppPage({super.key});
  @override
  Widget build(BuildContext context) => const StaticInfoPage(title: 'عن التطبيق', icon: Icons.favorite_rounded, paragraphs: []);
}
