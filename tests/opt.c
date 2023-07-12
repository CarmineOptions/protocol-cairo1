use array::ArrayTrait;
use option::OptionTrait;
use debug::PrintTrait;

use cubit::types::fixed::{FixedTrait, Fixed};
use cubit::types::fixed::{ONE};

use carmine_protocol::option_pricing;

// #[test]
// fn test_get_fixed() {
//     let res_1 = FixedTrait::from_unscaled_felt(2);
//     let res_2 = FixedTrait::from_felt(36893488147419103232);
//     assert(res_1 == res_2, 'wtf');
// }

#[test]
fn test_std_norm_cdf() {
    let mut test_data = get_std_norm_cdf_test_data();
    loop {  
        match test_data.pop_front() {
            Option::Some(x1) => {
                assert(x1 == 1, 'nope');
            },
            Option::None(()) => {
                break ();
            },
        };
    }
}


// This function just returns the same numbers we use in Cairo 0 tests(same since we have rng seed set)
// Will be deleted once fuzzy tests are available
// Returns array of tuples where first element is 'x' value for std and the second one is result calculated with python
// fn get_std_norm_cdf_test_data() -> Array<(u128, u128)> {
fn get_std_norm_cdf_test_data() -> Array<u128> {
    let mut test_data = ArrayTrait::<u128>::new();
    test_data.append(1_u128);
    test_data.append(1_u128);
    test_data.append(1_u128);
    test_data.append(1_u128);
    test_data.append(1_u128);
    return (test_data);
}
    // let mut test_data = ArrayTrait::<(u128, u128)>::new();
    // test_data.append((0_u128, 9223372036854775808_u128));
    // test_data.append((0_u128, 9223372036854775808_u128));
    // test_data.append((0_u128, 9223372036854775808_u128));
    // test_data.append((135583568941765197824_u128, 18446744073707724800_u128));
    // test_data.append((0_u128, 9223372036854775808_u128));
    // test_data.append((32097334688254619648_u128, 17691727896514895872_u128));
    // test_data.append((0_u128, 9223372036854775808_u128));
    // test_data.append((110311529560783126528_u128, 18446744053128738816_u128));
    // test_data.append((0_u128, 9223372036854775808_u128));
    // test_data.append((126360196904910422016_u128, 18446744073641437184_u128));
    // test_data.append((0_u128, 9223372036854775808_u128));
    // test_data.append((16602069666338596864_u128, 15051434047262978048_u128));
    // test_data.append((0_u128, 9223372036854775808_u128));
    // test_data.append((34495411417836863488_u128, 17879655947350405120_u128));
    // test_data.append((34495411417836863488_u128, 17879655947350405120_u128));
    // test_data.append((0_u128, 9223372036854775808_u128));
    // test_data.append((0_u128, 9223372036854775808_u128));
    // test_data.append((88175436672331661312_u128, 18446727905581592576_u128));
    // test_data.append((88175436672331661312_u128, 18446727905581592576_u128));
    // test_data.append((0_u128, 9223372036854775808_u128));
    // test_data.append((56447036865551228928_u128, 18426329339529998336_u128));
    // test_data.append((87437566909383278592_u128, 18446724361683111936_u128));
    // test_data.append((87437566909383278592_u128, 18446724361683111936_u128));
    // test_data.append((36893488147419103232_u128, 18027078212018366464_u128));
    // test_data.append((143884603774934499328_u128, 18446744073709494272_u128));
    // test_data.append((26009909143930466304_u128, 16984473595655288832_u128));
    // test_data.append((0_u128, 9223372036854775808_u128));
    // test_data.append((16048667344127309824_u128, 14902198471791099904_u128));
    // test_data.append((41505174165846491136_u128, 18221242355205881856_u128));
    // test_data.append((87068632027909079040_u128, 18446722320880670720_u128));
    // test_data.append((40398369521423917056_u128, 18183654425439002624_u128));
    // test_data.append((11068046444225730560_u128, 13387666999157014528_u128));
    // test_data.append((100165820320242860032_u128, 18446743553935163392_u128));
    // test_data.append((132078687567760392192_u128, 18446744073702109184_u128));
    // test_data.append((94631797098129997824_u128, 18446741401309642752_u128));
    // test_data.append((61058722883978616832_u128, 18438139039188393984_u128));
    // test_data.append((64194669376509239296_u128, 18442119347848585216_u128));
    // test_data.append((64194669376509239296_u128, 18442119347848585216_u128));
    // test_data.append((23796299855085322240_u128, 16629272543950831616_u128));
    // test_data.append((106622180746041212928_u128, 18446744004810385408_u128));
    // test_data.append((28223518432775614464_u128, 17284444899939524608_u128));
    // test_data.append((9038904596117680128_u128, 12690124923943684096_u128));
    // test_data.append((75262715820734971904_u128, 18446328692686344192_u128));
    // test_data.append((141486527045352259584_u128, 18446744073709391872_u128));
    // test_data.append((127098066667858804736_u128, 18446744073658093568_u128));
    // test_data.append((90389045961176809472_u128, 18446735234338283520_u128));
    // test_data.append((100719222642454151168_u128, 18446743634552911872_u128));
    // test_data.append((70466562361570484224_u128, 18445513199270760448_u128));
    // test_data.append((23980767295822417920_u128, 16661090308347731968_u128));
    // test_data.append((90573513401913901056_u128, 18446735673394991104_u128));
    // test_data.append((139272917756507111424_u128, 18446744073709150208_u128));
    // test_data.append((133001024771445866496_u128, 18446744073704390656_u128));
    // test_data.append((58291711272922185728_u128, 18432192439071756288_u128));
    // test_data.append((25640974262456274944_u128, 16929233027055218688_u128));
    // test_data.append((134845699178816815104_u128, 18446744073707087872_u128));
    // test_data.append((130418480601126535168_u128, 18446744073695260672_u128));
    // test_data.append((83194815772430073856_u128, 18446684280778498048_u128));
    // test_data.append((141302059604615168000_u128, 18446744073709379584_u128));
    // test_data.append((83563750653904273408_u128, 18446689670861121536_u128));
    // test_data.append((18631211514446647296_u128, 15564483753882648576_u128));
    // test_data.append((18631211514446647296_u128, 15564483753882648576_u128));
    // test_data.append((71573367005993058304_u128, 18445780632873013248_u128));
    // test_data.append((142962266571249025024_u128, 18446744073709465600_u128));
    // test_data.append((49437274117541601280_u128, 18378839616356618240_u128));
    // test_data.append((5349555781375769600_u128, 11327995770218541056_u128));
    // test_data.append((5349555781375769600_u128, 11327995770218541056_u128));
    // test_data.append((32835204451203002368_u128, 17754290557176524800_u128));
    // test_data.append((7194230188746725376_u128, 12022328364126126080_u128));
    // test_data.append((64379136817246339072_u128, 18442288995501875200_u128));
    // test_data.append((96107536624026763264_u128, 18446742331962150912_u128));
    // test_data.append((110864931882994401280_u128, 18446744056598044672_u128));
    // test_data.append((134292296856605540352_u128, 18446744073706471424_u128));
    // test_data.append((113816410934787932160_u128, 18446744067410911232_u128));
    // test_data.append((14572927818230546432_u128, 14485049666267133952_u128));
    // test_data.append((184467440737095520_u128, 9296962671809622016_u128));
    // test_data.append((127835936430807187456_u128, 18446744073670735872_u128));
    // test_data.append((45010055539851304960_u128, 18311277992904470528_u128));
    // test_data.append((106806648186778304512_u128, 18446744008789532672_u128));
    // test_data.append((46854729947222261760_u128, 18344500717558063104_u128));
    // test_data.append((141302059604615168000_u128, 18446744073709379584_u128));
    // test_data.append((141302059604615168000_u128, 18446744073709379584_u128));
    // test_data.append((62349994969138282496_u128, 18440058435952486400_u128));
    // test_data.append((85592892502012313600_u128, 18446711938634848256_u128));
    // test_data.append((85592892502012313600_u128, 18446711938634848256_u128));
    // test_data.append((73971443735575298048_u128, 18446184042108489728_u128));
    // test_data.append((19369081277395030016_u128, 15737672645836914688_u128));
    // test_data.append((82641413450218799104_u128, 18446675227657490432_u128));
    // test_data.append((137059308467661963264_u128, 18446744073708550144_u128));
    // test_data.append((100350287760979968000_u128, 18446743582283022336_u128));
    // test_data.append((100350287760979968000_u128, 18446743582283022336_u128));
    // test_data.append((136505906145450688512_u128, 18446744073708294144_u128));
    // test_data.append((43903250895428730880_u128, 18287063172025464832_u128));
    // test_data.append((116030020223633080320_u128, 18446744070781444096_u128));
    // test_data.append((42243043928794873856_u128, 18243633277516075008_u128));
    // test_data.append((127467001549333004288_u128, 18446744073664849920_u128));
    // test_data.append((81903543687270416384_u128, 18446661101289781248_u128));
    // test_data.append((122117445767957233664_u128, 18446744073378248704_u128));
    // test_data.append((147389485148939321344_u128, 18446744073709539328_u128));
    // test_data.append((135399101501028106240_u128, 18446744073707581440_u128));
    // test_data.append((10330176681277349888_u128, 13138883120260409344_u128));
    // test_data.append((25272039380982087680_u128, 16872435278029508608_u128));
    // test_data.append((33204139332677193728_u128, 17783946672546693120_u128));
    // test_data.append((67146148428302770176_u128, 18444229431627010048_u128));
    // test_data.append((103301766812773482496_u128, 18446743876004907008_u128));
    // test_data.append((103301766812773482496_u128, 18446743876004907008_u128));
    // test_data.append((5349555781375769600_u128, 11327995770218541056_u128));
    // test_data.append((5349555781375769600_u128, 11327995770218541056_u128));
    // test_data.append((112894073731102457856_u128, 18446744065078747136_u128));
    // test_data.append((112894073731102457856_u128, 18446744065078747136_u128));
    // test_data.append((138535047993558728704_u128, 18446744073709006848_u128));
    // test_data.append((51281948524912549888_u128, 18396606839314042880_u128));
    // test_data.append((51281948524912549888_u128, 18396606839314042880_u128));
    // test_data.append((88175436672331661312_u128, 18446727905581592576_u128));
    // test_data.append((75078248379997880320_u128, 18446310454049583104_u128));
    // test_data.append((133738894534394249216_u128, 18446744073705707520_u128));
    // test_data.append((114738748138473406464_u128, 18446744069124108288_u128));
    // test_data.append((64379136817246339072_u128, 18442288995501875200_u128));
    // test_data.append((66592746106091479040_u128, 18443919904814505984_u128));
    // test_data.append((9223372036854775808_u128, 12755231059699021824_u128));
    // test_data.append((84670555298326839296_u128, 18446703191481044992_u128));
    // test_data.append((84670555298326839296_u128, 18446703191481044992_u128));
    // test_data.append((56262569424814129152_u128, 18425637183130286080_u128));
    // test_data.append((133185492212182958080_u128, 18446744073704755200_u128));
    // test_data.append((37262423028893294592_u128, 18046602950252490752_u128));
    // test_data.append((37262423028893294592_u128, 18046602950252490752_u128));
    // test_data.append((2398076729582241792_u128, 10177378364586102784_u128));
    // test_data.append((2398076729582241792_u128, 10177378364586102784_u128));
    // test_data.append((553402322211286528_u128, 9444114509389760512_u128));
    // test_data.append((46854729947222261760_u128, 18344500717558063104_u128));
    // test_data.append((53311090373020606464_u128, 18411211786815639552_u128));
    // test_data.append((53311090373020606464_u128, 18411211786815639552_u128));
    // test_data.append((83932685535378456576_u128, 18446694594085773312_u128));
    // test_data.append((110680464442257309696_u128, 18446744055510220800_u128));
    // test_data.append((6456360425798342656_u128, 11747452040530444288_u128));
    // test_data.append((54417895017443180544_u128, 18417434601958125568_u128));
    // test_data.append((54417895017443180544_u128, 18417434601958125568_u128));
    // test_data.append((54417895017443180544_u128, 18417434601958125568_u128));
    // test_data.append((116030020223633080320_u128, 18446744070781444096_u128));
    // test_data.append((43534316013954539520_u128, 18278187548691247104_u128));
    // test_data.append((61427657765452808192_u128, 18438733945499123712_u128));
    // test_data.append((54602362458180272128_u128, 18418369380303214592_u128));
    // test_data.append((66777213546828578816_u128, 18444026840491511808_u128));
    // test_data.append((66777213546828578816_u128, 18444026840491511808_u128));
    // test_data.append((94631797098129997824_u128, 18446741401309642752_u128));
    // test_data.append((72495704209678540800_u128, 18445960586425231360_u128));
    // test_data.append((58660646154396377088_u128, 18433160347717455872_u128));
    // test_data.append((21398223125503078400_u128, 16177344395800526848_u128));
    // test_data.append((21398223125503078400_u128, 16177344395800526848_u128));
    // test_data.append((1660206966633859584_u128, 9884805734279903232_u128));
    // test_data.append((82641413450218799104_u128, 18446675227657490432_u128));
    // test_data.append((96292004064763854848_u128, 18446742423434950656_u128));
    // test_data.append((11252513884962826240_u128, 13448951029965619200_u128));
    // test_data.append((125068924819750764544_u128, 18446744073598709760_u128));
    // test_data.append((92787122690759049216_u128, 18446739549831546880_u128));
    // test_data.append((96107536624026763264_u128, 18446742331962150912_u128));
    // test_data.append((6825295307272534016_u128, 11885398704256165888_u128));
    // test_data.append((21767158006977269760_u128, 16251579546739527680_u128));
    // test_data.append((70097627480096292864_u128, 18445409487859032064_u128));
    // test_data.append((70097627480096292864_u128, 18445409487859032064_u128));
    // test_data.append((23611832414348226560_u128, 16597041675040309248_u128));
    // test_data.append((74155911176312389632_u128, 18446207290599346176_u128));
    // test_data.append((74155911176312389632_u128, 18446207290599346176_u128));
    // test_data.append((106622180746041212928_u128, 18446744004810385408_u128));
    // test_data.append((106622180746041212928_u128, 18446744004810385408_u128));
    // test_data.append((21767158006977269760_u128, 16251579546739527680_u128));
    // test_data.append((21767158006977269760_u128, 16251579546739527680_u128));
    // test_data.append((43534316013954539520_u128, 18278187548691247104_u128));
    // test_data.append((113078541171839549440_u128, 18446744065604136960_u128));
    // test_data.append((59029581035870568448_u128, 18434068616025481216_u128));
    // test_data.append((112709606290365366272_u128, 18446744064520200192_u128));
    // test_data.append((119534901597637902336_u128, 18446744072863559680_u128));
    // test_data.append((119534901597637902336_u128, 18446744072863559680_u128));
    // test_data.append((103855169134984773632_u128, 18446743907495514112_u128));
    // test_data.append((103855169134984773632_u128, 18446743907495514112_u128));
    // test_data.append((10514644122014443520_u128, 13201618095138877440_u128));
    // test_data.append((31174997484569141248_u128, 17607159382282301440_u128));
    // test_data.append((137243775908399071232_u128, 18446744073708621824_u128));
    // test_data.append((22689495210662748160_u128, 16429619312282200064_u128));
    // test_data.append((140010787519455494144_u128, 18446744073709256704_u128));
    // test_data.append((9592306918328967168_u128, 12884464358742505472_u128));
    // test_data.append((124515522497539473408_u128, 18446744073573187584_u128));
    // test_data.append((147573952589676412928_u128, 18446744073709539328_u128));
    // test_data.append((106068778423829921792_u128, 18446743991396999168_u128));
    // test_data.append((86515229705697804288_u128, 18446718874991466496_u128));
    // test_data.append((86515229705697804288_u128, 18446718874991466496_u128));
    // test_data.append((99796885438768676864_u128, 18446743492408844288_u128));
    // test_data.append((126360196904910422016_u128, 18446744073641437184_u128));
    // test_data.append((147573952589676412928_u128, 18446744073709539328_u128));
    // test_data.append((140748657282403876864_u128, 18446744073709334528_u128));
    // test_data.append((100350287760979968000_u128, 18446743582283022336_u128));
    // test_data.append((24903104499507896320_u128, 16814059807185719296_u128));
    // test_data.append((112156203968154075136_u128, 18446744062624667648_u128));
    // test_data.append((112156203968154075136_u128, 18446744062624667648_u128));
    // test_data.append((147389485148939321344_u128, 18446744073709539328_u128));
    // test_data.append((70282094920833392640_u128, 18445462331288383488_u128));
    // test_data.append((140564189841666785280_u128, 18446744073709318144_u128));
    // test_data.append((39660499758475534336_u128, 18155698588070637568_u128));
    // test_data.append((85039490179801038848_u128, 18446706934052282368_u128));
    // test_data.append((33388606773414289408_u128, 17798379876034809856_u128));
    // test_data.append((33388606773414289408_u128, 17798379876034809856_u128));



