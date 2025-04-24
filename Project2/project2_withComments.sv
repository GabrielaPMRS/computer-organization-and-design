/*Lembrando que:
  A base continua sendo o datapath monociclo*/
/*Modulo criado:
  hazardunit: Junta identificação de conflito para lw, basico de controle e identificação e tratamento do adiantamento.*/
  //Circuito sequencial: Com ajuda do clock cada parte do datapath executa partes de multiplas instrucoes
/*Funcionamento dos registradores:
  Cada dado precisa de um flipflop diferente:
  -flopr: tem apenas reset.
  -flopenr: Tem enable e reset.
  -flopenrc: Tem enable, reset e clear
  -floprc: tem reset e clear.
  Todos funcionam na borda de subida do clock, entao as informações que estao na sua entrada (estagio anterior) so são passadas para o registrador (e, portanto, o proximo estagio) com a subida do cock.
  Reset: Atua independente do clock para zerar as saidas do regsitrador a qualquer momento necessario.
  Enable: Depende do clock estar em subida para permitir a atualização dos valores dentro do flipflop.
  Clear: Depende do clock para limpar as saidas dos flipflops.*/
module hazardunit(
    // Sinais para detecção de hazards de dados
    input  logic [4:0] Rs1D, Rs2D, Rs1E, Rs2E, 
    input  logic [4:0] RdE, RdM, RdW,
    input  logic       RegWriteE, RegWriteM, RegWriteW,
    // Sinal para load hazard
    input  logic       ResultSrcEb0,
    // Sinal para control hazard
    input  logic       PCSrcE,
    // Sinais de controle
    output logic [1:0] ForwardAE, ForwardBE,
    output logic       StallF, StallD, FlushD, FlushE);
    /*Entradas:
      Rs1D: Indice de rs1 que sai de Register File, vai para regE.
      Rs2D: Indice de rs2 que sai de Register File, vai para regE.
      Rs1E: Indice de rs1 que sai de regE (vai para ULA)
      Rs2E: Indice de rs2 que sai de regE (vai para ULA)
      RdE: indice de rd saindo de regE (carregado pelos resgistradores ate ser usado no write back/ register file).
      RdM: Indice rd saindo de regM (grupo de regsitradores antes de Memory Write), que continua o "carregamento" iniciado por RdE. 
      RdW: Indice rd saindo de regW (grupo de regsitradores depois de Memory Write), que continua o "carregamento" de regM. 
      RegWriteE: Controle de escrita em regsitrador saído/carregado de regE
      RegWriteM: Controle de escrita em regsitrador saído/carregado de regM
      RegWriteW: Controle de escrita em regsitrador saído/carregado de regW
      ResultSrcEb0: Sinal de controle usado para definir o conteudo de write back (aqui só usando o bit 0(mais significante)).
        Quando ResultSrcEb0=1 há escrita de valores inteiros lidos de Data Memory (especificamente a instruçao lw).
      PCSrcE: Sinal de controle para branch saindo de regE.
        calculado em regE usando JumpE, BranchE e ZeroE para ser aplicado no proximo pulso de clock.
          O sinal já pe passado para o mux de PCSrc e já define uma saida para o mux, mas o pcreg só vai ser atualizado com esse valor no proximo pulso.
    Saidas:
      FowardAE: Controle do mux que faz filtragem da entrada A na ULA.
      FowardBE: Controle do mux que faz filtragem da entrada B na ULA
      StallF: Sinal que identifica e executa a bolha/stall no regF (sem atualizar PC).
      StallD: Sinal que executa stall em regD ("impede" a propragação da instrução com "defeito" adiante). 
        Trabalha junto com FLushD mas tem "mias importancia" para brecar os dados.
      FlushD: Sinal que funciona como clear para os registradores de regD (quando flushd=0 não ha cancelamento de escrita em regD).
        Acredito que funcione mais como complemento para StallD, já que é ele que "segura" a proxima instrução de avançar.
      FlushE: Sinal de controle que funciona como clear do regE ("limpa" os dados que iriam pra ULA, fazendo parte da bolha).*/
      //StallD e StallF funcionam como enable: quando=1 permitem a atualização de valores na subida do clock (sincrono com clock).
    always_comb begin
        // Forward para A
        if ((Rs1E != 0) && (Rs1E == RdM) && RegWriteM) 
            ForwardAE = 2'b10;  // Forward do estágio Memory
        else if ((Rs1E != 0) && (Rs1E == RdW) && RegWriteW) 
            ForwardAE = 2'b01;  // Forward do estágio Writeback
        else 
            ForwardAE = 2'b00;  // Sem forwarding
            
        // Forward para B
        if ((Rs2E != 0) && (Rs2E == RdM) && RegWriteM) 
            ForwardBE = 2'b10;  // Forward do estágio Memory
        else if ((Rs2E != 0) && (Rs2E == RdW) && RegWriteW) 
            ForwardBE = 2'b01;  // Forward do estágio Writeback
        else 
            ForwardBE = 2'b00;  // Sem forwarding
    end
    /*Detecção e controle de adiantamento:
      Detecção: De forma geral acontece quando um registrador "saida" de uma instrução é usado logo em seguida como entrada de outra instrução.
      Como isso pode acontecer tanto com rs1 quanto rs2, se aplica essa mesma verificação duas vezes, uma para cada entrada
      Rs1E: Rs1 que sai do regE (entre Register File e ULA)
      Rs2E: Rs2 que sai de regE (entre Register File  e ULA)
      RdM: rd que sai de regM(entre ULA e Data memory)
      RdW: rd que sai de regW (entre Data Memory e Write back)
      RegWriteM; Sinal de controle que indica escrita na memoria (Data Memory)
      RegWriteW: Sinal de controle que indica escrita no regsitrador (Write Back -> Register File).
      FowardAE: Controle do mux com saida SrcAE (entrada A para ULA).
        Necessario porque pode receber ou RD1 (de rs1) ou adiantamento.
      FowardBE: Controle do mux com saida SrcAE (entrada B para ULA)
        Necessario pois pode receber RD2 (de rs2), immediato ou adiantamento.
      Pensando em que cada etapa executa sua propria funcção, porem todos sincronos (usando como referencia o mesmo clock):
      Num mesmo pulso de clock, Rs1E e Rs2E representam os dados de uma instruçao que veio por ultimo em relaçao a RdM (do data memory) e RdW(do write back).
        A ordem de execucao seria (do primeiro ao ultimo): RdW, RdM e (Rs1E e Rs2E).
      Para nao repetir muitas linhas parecidas, usar RsE e FowardE:
      Quando RsE==RdM, significa que o rd atualmente em Data Memory (em teoria, 1 ciclo a frente) tem sua saisa usada como entrada.
        Quando RegWriteM há uma escrita em register file "detectada" no "inicio" de Data Memory (como R-type).
          Assim FowardE=10 para fazer o adiantamento seja feito logo depois de regM com o valor ALUResultM (resultado da ULA saindo de regM).
      Quando RsE==RdW, singifica que o rd atualmente em Write back/Register File (em teoria, 2 ciclos a frente) tem sua saisa usada como entrada.
        Quando RegWriteW ha escrita em register file identificada em Write back (para lw, por exemplo).
          Assim FowardE=01 para fazer o adiantamento logo depois de RegW com o valor ResultW (resultado do mux Result no write back).
      Quando nenhum desses é verdade, significa que nao é necessario adiantamento (ULA recebe rs1 e rs2 da instrução em Register File)
        Portanto FowardE=00.
      Quando RsE!=0 se confirma que nenhum dos regsitradores envolvidos é x0 (pois ele é padronizado para armazenar apenas 0, mas é uma norma humana, só há essa verificação para impedir uma sobre escrita).
      */
    // Detecção de load hazard (load seguido por instrução que usa o resultado)
    logic lwStall;
    assign lwStall = ResultSrcEb0 && ((Rs1D == RdE) || (Rs2D == RdE));
    /*Controle de bolha para lw (que também pe usado para leve direcionamento nos conflitos de controle):
      ResultsrcEb0=1 -> Dado lido da memoria para escrever (load word)
      RsD==RdE: A instrução a seguir usa essa informação (que ainda nao foi devidamente escrita para ser acessada), causando conflito.*/
    // Controle de stalls e flushes
    assign StallF = lwStall;        // Stall fetch em caso de load hazard
    assign StallD = lwStall;        // Stall decode em caso de load hazard
    /*Sinais de Stall: serve como  enable
    -Quando=1: Permite atualização
    -Quando=0: nao permite atualização
      StallF: Faz enable em pcreg
      StallD: Faz enable em regD
    Como se passa ~Stall (em datapath), a logica é que ao identificar o conflito de lw(lwStall=1) há a necessidade de bolha nesses 2 registradores (Satll=1)
      o que significa que as informações nao devem ser atualizadas (~Stall)
    */
    // Flush em caso de branch/jump ou load stall
    assign FlushE = lwStall || PCSrcE;  // Flush execute em caso de branch/jump ou load stall
    assign FlushD = PCSrcE;          // Flush decode em caso de branch/jump
    /*Sinais de Flush: funcionam como clear nos registradores (sincrno com clock, zera as saidas).
    -Quando =1: Permite a "limpa".
    -Quando=0: Nao permite a limpeza.
     FlushE: Zera as saidas de regE, aplicando uma parte da bolha em EX.
     FlushD: Zera as saidas de regD, 
    FlushE é necessario tanto para o conflito de dados quanto de controle, por isso lwStall||PCSrcE.
    FlushD é apenas necessario quando ha conflito de controle.
      É o registrador que armazana a instrucao ja interpretada. 
      Quando se tem pulso de clock as informações de regF sao atualizadas com elas.
      Ai inicia a geração de sinais de controle, Register File e o extend(immediato).*/
endmodule

module top(input  logic        clk, reset, 
           output logic [31:0] WriteDataM, DataAdrM, 
           output logic        MemWriteM);
  /*top() funciona como main() de C, faz controle de:
  imem(): Instruction Memory.
  dmem(): Data Memory.
  riscvsingle(): "Caminho" completo da inforação: controller() e datapath().*/
  /*entradas: 
    clock, reset: importante para controle das informações do controle para datapath.
  saidas:
    WriteDataM: informaçao a ser escrita em Write Register e MemWrite, saindo de regM 
    DataAdrM: Endereço, saindo de regM
    MemWriteM: Sinal de controle para fazer escrita na memoria, saindo de regM.*/
  /*Fios locais (representam "variáveis globais"):
  PC: Endereço com instrucao atualmente executada.
  Instr: INstrução extraída de PC.
  Read Data: Informação obtida ao executar Instr.*/
  logic [31:0] PCF, InstrF, ReadDataM;
  /*Sinais locais:
    PCF: Endereço com a instrucao que vai ser interpretada pelo INstruction Memory
      Definido como saida em riscv.
    InstrF: Instrucao que sai de regF (a instrucao ja lida).
    ReadDataM: INstrução pronta para execucao */
    /*OBS:
      No diagrama de referencia, tanto PCF quanto InstrF recebem o nome PCF.
      Aqui PCF é a entrada e InstrF é a saida de pcreg
      Alem de que nao importa a ordem de declaracao:
        Mesmo que a ordem esteja riscv, imem e dmem, quem vai primeiro é imem, depois dmem e por fim riscv.*/
  //declarando modulos utilizados nesse circuito:
  riscv riscv(clk, reset, PCF, InstrF, MemWriteM, DataAdrM, //controle+datapath
              WriteDataM, ReadDataM);
  imem imem(PCF, InstrF); //leitura da instrucao e colocada em InstrF
  dmem dmem(clk, MemWriteM, DataAdrM, WriteDataM, ReadDataM); //alinhamento de bits
endmodule

module riscv(input  logic        clk, reset,
             output logic [31:0] PCF,
             input  logic [31:0] InstrF,
             output logic        MemWriteM,
             output logic [31:0] ALUResultM, WriteDataM,
             input  logic [31:0] ReadDataM);
  /*riscvsingle() representa o processador projetado para RISC-V, que contém controle +datapath+controle de conflito.*/
  /*Entradas:
    clk e reset: Para controller (define ritmo de execução e restart, respectivamente).
    InstrF: Instrucao ja lida por instruction memory
    ReadDataM: Instrucao pronta para executar por causa de instruction memory
  Saídas:
    PCF: Endereço da instrução atual.
    MemWrite: Sai de controller para definir em Data Memory (dmem) se escrita na memória.
      Memória obtida pela ULA, em ALUResult.
    ALUResult: Resultado da ULA (valor ou endereço).
    WriteData: Recebe Read Register 2 para ser ecrito com MemWrite.*/
  logic [6:0]  opD;
  logic [2:0]  funct3D;
  logic        funct7b5D;
  logic [1:0]  ImmSrcD;
  logic        ZeroE;
  logic        PCSrcE;
  logic [2:0]  ALUControlE;
  logic        ALUSrcE;
  logic        ResultSrcEb0;
  logic        RegWriteM;
  logic [1:0]  ResultSrcW;
  logic        RegWriteW;
  /*Declaração dos sinais de controle a serem calculados por controller:
  opD: Opcode vindo de Register File (criado no estagio de registser file) (mandado para controller)
  funct3D: fcuntion3 (complemento do opcode) saindo de Regsister File(mandado para controller)
  function7b5D: function7 (complemento de opcode) bit 5 saindo de Register File(mandado para controller)
    O que diferencia a declaraçao de um add de sub (pelo q me lembro)
  ImmSrcD: Controle que indica qual forma se obtera o immediato a partir da instrucao completa.
    Criada no register file e ja utilizada no mesmo estagio e pulso de clock.
  ZeroE: Sinal especial da ULA para verificar se uma subtração(comparação) é verdadeira.
    Criada em EX e já utilizado para fomrar PCSRcE.
  PCSrcE: SInal de controle que controla o mux inicial para o proximo endereço de instrucao.
    Recebe E no nome pois é formado por ZeroE (sinal calculado em EX), BranchE e JumpE (sinais carregados até EX para serem utilizados nesse estagio).
  ALUControlE: Sinal de controle que determina a operação executada pela ULA saindo de regE (e indo instantanemanete (no mesmo pulso de clock) para a ULA).
  ALUSrcE: Sinal de controle para o "segundo" mux da entrada B da ULA.
    O que também esta presente na parte do monociclo O que decide entre um valor inteiro
      No monociclo sendo RD2, agora tendo também a possibilidade de ser os possiveis adiantamentos.
    Ou o immediato calculado pelo extend.
  ResultSrcEb0: Sinal de controle para filtrar o que sera esccrito nos regsitradores em write back
    Como o sinal para "passar" um dado lido na memoria é 10, é possivel usar o bit 0 para identificar se acontece um lw ou nao.
  RegWriteM: Sinal de controle para permitir a escrita no Register File, saindo de regM
    Esse sinal precisa ser carregado ao longo de todo circuito para garantir que só seja usado quando Write Data e Write Register estejam de acordo.
  ResultSrcW: Sinal de controle para o ultimo mux, porem inteiro e saindo de regW. 
  RegWriteW: Sinal de controle para permitir a escrita no Register File, saindo de regW (onde vai ser efetivamente usado).
  */
  logic [1:0]  ForwardAE, ForwardBE;
  logic        StallF, StallD, FlushD, FlushE;
  //declara os sinais de controle de conflito (usados em hazardunit).
  logic [4:0]  Rs1D, Rs2D, Rs1E, Rs2E, RdE, RdM, RdW;
  //dados da primeira instrucao lida que vao ser passados de regsitrador em registrador.
  /*A letra maiuscula ao final indica para onde a informação vai ser passada:
    Rs1E indica que vem do regsitrador ID/EX (que esta antes da ULA), entao suas informações alimentarao a ULA.*/
  logic        RegWriteE;  // Sinal adicionado para a hazard unit
  //Adicionado na construcao de sinais de controle para avisar "antecipadamente" ao harzardunit que havera escrita no Register File (lw).
  //É captado durante o estgaio de execucao, assim hazardunit ja consegue detectar se a instrucao "recente" depende da "antiga" antes do conflito acontecer.
  controller c(clk, reset,
               opD, funct3D, funct7b5D, ImmSrcD,
               FlushE, ZeroE, PCSrcE, ALUControlE, ALUSrcE, ResultSrcEb0,
               MemWriteM, RegWriteM, 
               RegWriteW, ResultSrcW,
               RegWriteE);  // Adicionado RegWriteE à interface
  //chamada do controle controller (com adiçao de de RegWriteE, sinal que ajuda na detecçao de conflitos).
  datapath dp(clk, reset,
              StallF, PCF, InstrF,
              opD, funct3D, funct7b5D, StallD, FlushD, ImmSrcD,
              FlushE, ForwardAE, ForwardBE, PCSrcE, ALUControlE, ALUSrcE, ZeroE,
              MemWriteM, WriteDataM, ALUResultM, ReadDataM,
              RegWriteW, ResultSrcW,
              Rs1D, Rs2D, Rs1E, Rs2E, RdE, RdM, RdW);
  //chamada do datapath dp
  // Instância da unidade de controle de conflitos (hazard unit)
  hazardunit hu(
      .Rs1D(Rs1D), .Rs2D(Rs2D), 
      .Rs1E(Rs1E), .Rs2E(Rs2E), 
      .RdE(RdE), .RdM(RdM), .RdW(RdW),
      .RegWriteE(RegWriteE), .RegWriteM(RegWriteM), .RegWriteW(RegWriteW),
      .ResultSrcEb0(ResultSrcEb0),
      .PCSrcE(PCSrcE),
      .ForwardAE(ForwardAE), .ForwardBE(ForwardBE),
      .StallF(StallF), .StallD(StallD), .FlushD(FlushD), .FlushE(FlushE)
  );
  /*Chamda do controle de conflitos.
    Essa instancia é chamada de instancia por nome, usando a logica .nome_porta(sinal).
      Permite um entendimento melhor do que cada porta recebe como sinal.
    Aqui seria algo do tipo Porta Rs1D recebe o sinal Rs1D, por exemplo.*/
endmodule

module controller(input  logic       clk, reset,
                  // Decode stage control signals
                  input logic [6:0]  opD,
                  input logic [2:0]  funct3D,
                  input logic        funct7b5D,
                  output logic [1:0] ImmSrcD,
                  // Execute stage control signals
                  input logic        FlushE, 
                  input logic        ZeroE, 
                  output logic       PCSrcE,        // for datapath and Hazard Unit
                  output logic [2:0] ALUControlE, 
                  output logic       ALUSrcE,
                  output logic       ResultSrcEb0,  // for Hazard Unit
                  // Memory stage control signals
                  output logic       MemWriteM,
                  output logic       RegWriteM,     // for Hazard Unit                 
                  // Writeback stage control signals
                  output logic       RegWriteW,     // for datapath and Hazard Unit
                  output logic [1:0] ResultSrcW,
                  // Adicionado para a hazard unit
                  output logic       RegWriteE);    // for Hazard Unit
  /*Entradas:
    clk, reset: importantes para controlar os regsitradores que guardam esses sinais de controle.
  opD: Opcode vindo de Register File (criado no estagio de registser file) (mandado para controller)
  funct3D: fcuntion3 (complemento do opcode) saindo de Regsister File(mandado para controller)
  function7b5D: function7 (complemento de opcode) bit 5 saindo de Register File(mandado para controller)
    O que diferencia a declaraçao de um add de sub (pelo q me lembro)
  ImmSrcD: Controle que indica qual forma se obtera o immediato a partir da instrucao completa.
    Criada no register file e ja utilizada no mesmo estagio e pulso de clock.
  ZeroE: Sinal especial da ULA para verificar se uma subtração(comparação) é verdadeira.
    Criada em EX e já utilizado para fomrar PCSRcE.
  Saidas:
    PCSrcE: SInal de controle que controla o mux inicial para o proximo endereço de instrucao.
      Recebe E no nome pois é formado por ZeroE (sinal calculado em EX), BranchE e JumpE (sinais carregados até EX para serem utilizados nesse estagio).
    ALUControlE: Sinal de controle que determina a operação executada pela ULA saindo de regE (e indo instantanemanete (no mesmo pulso de clock) para a ULA).
    ALUSrcE: Sinal de controle para o "segundo" mux da entrada B da ULA.
      O que também esta presente na parte do monociclo O que decide entre um valor inteiro
        No monociclo sendo RD2, agora tendo também a possibilidade de ser os possiveis adiantamentos.
      Ou o immediato calculado pelo extend.
    ResultSrcEb0: Sinal de controle para filtrar o que sera esccrito nos regsitradores em write back
      Como o sinal para "passar" um dado lido na memoria é 10, é possivel usar o bit 0 para identificar se acontece um lw ou nao.
    RegWriteM: Sinal de controle para permitir a escrita no Register File, saindo de regM
      Esse sinal precisa ser carregado ao longo de todo circuito para garantir que só seja usado quando Write Data e Write Register estejam de acordo.
    ResultSrcW: Sinal de controle para o ultimo mux, porem inteiro e saindo de regW. 
    RegWriteW: Sinal de controle para permitir a escrita no Register File, saindo de regW (onde vai ser efetivamente usado).
  */
  // pipelined control signals
  logic        RegWriteD;
  logic [1:0]  ResultSrcD, ResultSrcE, ResultSrcM;
  logic        MemWriteD, MemWriteE;
  logic        JumpD, JumpE;
  logic        BranchD, BranchE;
  logic [1:0]  ALUOpD;
  logic [2:0]  ALUControlD;
  logic        ALUSrcD;
  /*Sinais de saida (quando possuem D ao final, significa que estao saindo diretamente do controle)
  RegWriteD: sinal que indica escrita de regsitrador (write back).
  ResultSrcD: Sinal que controla mux de "resultado final" (o que sera escrito no Write back).
  ResultSrcE: Sinal de controle do "resultado final" mas saindo de regE.
    ResultSrcD sendo carregado adiante ate ser devidamente usado em write back.
  ResultSrcM: ResultSrcD, porem sendo carregado e saindo de regM.
  MemWriteD: Sinal que indica escrita na memoria (data memory) para instrucoes como sw.
    Saindo diretamente da unidade de controle.
  MemWriteE: MemWriteD sendo carregado, saindo de regE.
    So é devidamente usando em Data Memory
    O carregamento vai ate MemWriteM.
  JumpD: Sinal que indica ocorrencia de Jump (pulo incondicional).
  JumpE: JumpD sendo carregado, saindo de regE.
    É usado apenas em EX.
  BranchD: Sinal que indica uma condiçao a ser confirmada (pulo condicional.)
  BranchE: BranchD sendo carregado, saindo de regE.
    Também é apenas usado em EX.
  ALUOpD: Dois ultimos bits do opcode, serve como entrada de aludec para definir os controles da ULA baseada no tipo de instrucao.
  ALUControlD: Controle de 3 bits que na ULA, determina qual operação será feita (saida de aludec).
  ALUSrcD: Sinal que faz controle entre entrada de regsitrador ou immediato como entradaB para ULA.*/
  // Decode stage logic
  maindec md(opD, ResultSrcD, MemWriteD, BranchD,
             ALUSrcD, RegWriteD, JumpD, ImmSrcD, ALUOpD);
  //declaracao de maindec(controle para todos os outros sinais do circuito).
  aludec  ad(opD[5], funct3D, funct7b5D, ALUOpD, ALUControlD);
  //Declaraçao do aludec (controle focado em determinar ALUSrcD e immediato).
  //A seguir a declaração de cada conjunto de resistores para propagar os sinais de controle
    //Divididos de acordo com os estagios aos quais pertencem.
  floprc #(10) controlregE(clk, reset, FlushE,
                           {RegWriteD, ResultSrcD, MemWriteD, JumpD, BranchD, ALUControlD, ALUSrcD},
                           {RegWriteE, ResultSrcE, MemWriteE, JumpE, BranchE, ALUControlE, ALUSrcE});
  /*O regsitrador de controle em EX tem:
    clk, reset: Controles basicos de qualquer regsitrador flipflop.
    FlushE: Funciona como o clear dos registradores:
      Quando=1 faz com que a subida do clock xere as saidas.
      é sincrono ao clock (so presta de algo quando clock estiver na borda de subida).
      Ao contrario do reset que é assincrono(a qualquer momento pode ser utiliado, independente de pulso).
    {RegWriteD, ResultSrcD, MemWriteD, JumpD, BranchD, ALUControlD, ALUSrcD}
      Todos sinais de entrada (a serem armazenados) juntos num "unico sinal".
    {RegWriteE, ResultSrcE, MemWriteE, JumpE, BranchE, ALUControlE, ALUSrcE}
      Todas as saidas (valores finais atualizados) juntos num "unico sinal".
  Usa FlushE por causa do stall: Evita que a instrucao responsavel pelo conflito avançe para a esecucao
    Antes da anterior ter sido devidamente resolvida.*/
  assign PCSrcE = (BranchE & ZeroE) | JumpE;
  assign ResultSrcEb0 = ResultSrcE[0];
  /*PCSrcE: =1 quando ha presença de jal (JumpE=1) ou quando tem condicional atendido ((BranchE & ZeroE)).
  ResultSrcEb0: Parte especifica de ResultSrcE (sinal geral).
    O bit 0 de ResultSrcE permite identificar imediatamente que se trata de lw.
      Pois significa que o dado passado para escrita no Write Back foi lido da memoria (lw)
    Os outros dois casos (para R-type e jal) possuem o mesmo bit).
      Para diferenciar ambos seria necessario os dois bits de controle.
      Como com esse sinal especifico se pretende identificar necessidade de bolhas por conflitos de dados, essa especificao nao é necessaria.*/
  // Memory stage pipeline control register
  flopr #(4) controlregM(clk, reset,
                         {RegWriteE, ResultSrcE, MemWriteE},
                         {RegWriteM, ResultSrcM, MemWriteM});
  /*Registrador com sinais de controle para Data Memory:
    clk, reset: Sao flipflops basicos, aqui nao é necessario bolha.
    {RegWriteE, ResultSrcE, MemWriteE}
      Sinais de entrada (a serem guardados) vindo diretamente do controle.
    {RegWriteM, ResultSrcM, MemWriteM}
      Sinais de saida (valores ja atualizados) saindo de regE.
  */
  // Writeback stage pipeline control register
  flopr #(3) controlregW(clk, reset,
                         {RegWriteM, ResultSrcM},
                         {RegWriteW, ResultSrcW});     
  /*Regsitradores para os sinais usados no Write back:
    clk, reset: Flipflops basicos (nem necessidade de bolha, portanto sem necessidade de flush).
    {RegWriteM, ResultSrcM}: Sinais de entrada, recebidos de regM
    {RegWriteW, ResultSrcW}: Sinais de saida, saindo de regW e sendo finalmente usados.
  */
  //OBS: A medida que as etapas vao passando, vai precisando carregar menos sinais adiante
    //Dessa forma os ultimos estagios tem regsitradores menores comparados aos primeiros.
endmodule

module maindec(input  logic [6:0] op,
               output logic [1:0] ResultSrc,
               output logic       MemWrite,
               output logic       Branch, ALUSrc,
               output logic       RegWrite, Jump,
               output logic [1:0] ImmSrc,
               output logic [1:0] ALUOp);

  logic [10:0] controls;

  assign {RegWrite, ImmSrc, ALUSrc, MemWrite,
          ResultSrc, Branch, ALUOp, Jump} = controls;

  always_comb
    case(op)
    // RegWrite_ImmSrc_ALUSrc_MemWrite_ResultSrc_Branch_ALUOp_Jump
      7'b0000011: controls = 11'b1_00_1_0_01_0_00_0; // lw
      7'b0100011: controls = 11'b0_01_1_1_00_0_00_0; // sw
      7'b0110011: controls = 11'b1_xx_0_0_00_0_10_0; // R-type 
      7'b1100011: controls = 11'b0_10_0_0_00_1_01_0; // beq
      7'b0010011: controls = 11'b1_00_1_0_00_0_10_0; // I-type ALU
      7'b1101111: controls = 11'b1_11_0_0_10_0_00_1; // jal
      7'b0000000: controls = 11'b0_00_0_0_00_0_00_0; // need valid values at reset
      default:    controls = 11'bx_xx_x_x_xx_x_xx_x; // non-implemented instruction
    endcase
endmodule

module aludec(input  logic       opb5,
              input  logic [2:0] funct3,
              input  logic       funct7b5, 
              input  logic [1:0] ALUOp,
              output logic [2:0] ALUControl);

  logic  RtypeSub;
  assign RtypeSub = funct7b5 & opb5;  // TRUE for R-type subtract instruction

  always_comb
    case(ALUOp)
      2'b00:                ALUControl = 3'b000; // addition
      2'b01:                ALUControl = 3'b001; // subtraction
      default: case(funct3) // R-type or I-type ALU
                 3'b000:  if (RtypeSub) 
                            ALUControl = 3'b001; // sub
                          else          
                            ALUControl = 3'b000; // add, addi
                 3'b010:    ALUControl = 3'b101; // slt, slti
                 3'b110:    ALUControl = 3'b011; // or, ori
                 3'b111:    ALUControl = 3'b010; // and, andi
                 default:   ALUControl = 3'bxxx; // ???
               endcase
    endcase
endmodule

module datapath(input logic clk, reset,
                // Fetch stage signals
                input  logic        StallF,
                output logic [31:0] PCF,
                input  logic [31:0] InstrF,
                // Decode stage signals
                output logic [6:0]  opD,
                output logic [2:0]	funct3D, 
                output logic        funct7b5D,
                input  logic        StallD, FlushD,
                input  logic [1:0]  ImmSrcD,
                // Execute stage signals
                input  logic        FlushE,
                input  logic [1:0]  ForwardAE, ForwardBE,
                input  logic        PCSrcE,
                input  logic [2:0]  ALUControlE,
                input  logic        ALUSrcE,
                output logic        ZeroE,
                // Memory stage signals
                input  logic        MemWriteM, 
                output logic [31:0] WriteDataM, ALUResultM,
                input  logic [31:0] ReadDataM,
                // Writeback stage signals
                input  logic        RegWriteW, 
                input  logic [1:0]  ResultSrcW,
                // Hazard Unit signals 
                output logic [4:0]  Rs1D, Rs2D, Rs1E, Rs2E,
                output logic [4:0]  RdE, RdM, RdW);
  /*
  clk, reset: Necessario para o mesmo controle de clock em todos os regsitradores entre estagios
    Independente da complexidade
  StallF: Enable dos regsitrador de dados (endereços de instrucao)pcreg(regF).
  PCF: Endereço de instrução atual
  InstrF: INstruçao obtida pela leitura de PCF.
  opD: opcode saido de INstrD (que vem de regD)
    Passado para a unidade de controle.
  funct3D:fcuntion3 (complemento do opcode) saindo de Regsister File(mandado para controller)
  function7b5D: function7 (complemento de opcode) bit 5 saindo de Register File(mandado para controller)
    O que diferencia a declaraçao de um add de sub (pelo q me lembro)
  StallD: Enable pros registradores de dados do regD.
  FlushD: Clear rps regsitradores de dados de regD.
    Importante pra lidar com os erros dos conflitos de controle.
  ImmSrcD: Controle que indica qual forma se obtera o immediato a partir da instrucao completa.
    Criada no register file e ja utilizada no mesmo estagio e pulso de clock.
  FlushE: Clear para regsitradores de dados de regE
  ForwardAE: Sinal de controle pra entradaA da ULA.
  ForwardBE: Sinal de primeiro controle pra entradaB da ULA.
  PCSrcE: Sinal de controle pra decidir o proximo endereço de PC, gerado em EX.
  ALUControlE: Sinal de controle para determinar operação da ULA, saindo de regE
    Carregado diretamente da COntrol Unit.
  ALUSrcE: Controle do segundo MUX para entradaB da ULA, saindo de regE.
    Carregado diretamente da COntrol Unit.
  ZeroE: Sinal especial da ULA para verificar se uma subtração(comparação) é verdadeira.
    Criada em EX e já utilizado para fomrar PCSRcE.
  MemWriteM: Sinal de controle para indicar escrita na memoria, saindo de regM (onde vai ser usado)
  WriteDataM: Dado a ser escrito na memoria (em caso de sw), saindo de regM (onde vai ser usado).
  ALUResultM: Resultado da ULA, saindo de regM.
  ReadDataM: Dado lido da memoria (em caso de LW), gerado em Data Memory (e indo para regW).
  RegWriteW: SInal que indica escrita em regstrador, saindo de regW
  ResultSrcW: Sinal de controle do que vai ser escrito no write back, saindo de regW
  Rs1D: indice do regsitrador 1, saindo de Register FIle
  Rs2D: indice do regsitrador 2, saindo de Register FIle
  Rs1E: indice do regsitrador 1, saindo de regE
  Rs2E: indice do regsitrador 2, saindo de regE
  RdE: Indice do regsitrador de resultado saindo de regE
  RdM: Indice do regsitrador de resultado saindo de regM
  RdW: Indice do regsitrador de resultado saindo de regW (registrador depois de EX e antes de Data MEmory).*/
  // Fetch stage signals
  logic [31:0] PCNextF, PCPlus4F;
  /*PCNextF: Saida do mux para escolher o endereço PC 
    (no esquematico de referencia é a entrada do clock PCF)
  PCPlus4F: Endereço de fluxo de processamento normal (sem pulo no codigo)
    Calculado por somador dedicado em IF (Instruction Memory)*/
  // Decode stage signals
  logic [31:0] InstrD;
  logic [31:0] PCD, PCPlus4D;
  logic [31:0] RD1D, RD2D;
  logic [31:0] ImmExtD;
  logic [4:0]  RdD;
  /*InstrD: INstrução lida de PCF.
  PCD: Endereço PC atual, saindo de regD (passando por regsiter file) e indo para regE.
  PCPlus4D: Proximo PC seguindo o fluxo normal de processamento.
    Calculado em IF nesse fio esta saindo de regD
  RD1D: Dado lido de Rs1D.
  RD2D: Dado lido de Rs2D.
  ImmExtD: Instrução passada para extend para calcular o immediato, gerado em exttend
    No mesmo estagio de Register File.
  RdD: Indice do registrador de escrita saindo de regD.*/
  // Execute stage signals
  logic [31:0] RD1E, RD2E;
  logic [31:0] PCE, ImmExtE;
  logic [31:0] SrcAE, SrcBE;
  logic [31:0] ALUResultE;
  logic [31:0] WriteDataE;
  logic [31:0] PCPlus4E;
  logic [31:0] PCTargetE;
  /*
  RD1E: Dado lido de Rs1D, saindo de regE.
  RD2E: Dado lido de Rs2D, saindo de regE
  PCE: Endereço de instrução atual, saindo de regE.
  ImmExtE: Immediato calculado em Decode, saindo de regE.
  SrcAE: EntradaA final da ULA.
  SrcBE: EntradaB final da ULA.
  ALUResultE: Resultado da ALU, saindo diretamente do estagio EX.
  WriteDataE: Dado a se escrever em Data Memory (em caso de sw), saindo de regE.
    No caso de nao houver adiantamento, o que sairá do primeiro MUX na entradaB é RD2E
    Que é o dado a se escrever no sw.
  PCPlus4E; Novo endereço de PC (considerando fluxo normal de processamento), saindo de regE.
  PCTargetE: Novo endereço de PC(considerando pulo no fluxo de processamento), saindo de regE.*/
  // Memory stage signals
  logic [31:0] PCPlus4M;
  /*Variavel local para transportar PCPlus4E adiante, saindo de regM.*/
  // Writeback stage signals
  logic [31:0] ALUResultW;
  logic [31:0] ReadDataW;
  logic [31:0] PCPlus4W;
  logic [31:0] ResultW;
  /*ALUResultW: Resultado da ALU, saindo de regW.
    Dado é carregado de Memory para Write back, para isso passa pelo regW.
    Usado em R-type.
  ReadDataW: Dado lido do endereço obtido pela ULA, em Data Memory, saindo de regW.
    Usando em lw.
  PCPlus4W: Endereço futuro (no fluxo padrao), saindo de regW.
    Usado em jal (serve como endereço de retorno).
  ResultW: Saida final do ResultMux (que decide o que és escrito na memoria)
    Tendo como entradas as ultimas 3 informações.*/
  // Fetch stage pipeline register and logic
  mux2    #(32) pcmux(PCPlus4F, PCTargetE, PCSrcE, PCNextF);
  //MUX para controle do proximo endereço de instrucao (entrada de pcreg).
  flopenr #(32) pcreg(clk, reset, ~StallF, PCNextF, PCF);
  /*Registrador de pcreg, que guarda o endereço da instrução atual.
  clk, reset: Controle basico desse regsitrador.
  ~StallF: Clear do regsitrador.
    Na logica de: Stalllw=1, StallF=1, logo a informação nao deve ser atualizada (clear=0).
  PCNext: Saida atualizada.
  PCF: Entrada do registrador.*/
  adder         pcadd(PCF, 32'h4, PCPlus4F);
  //somador dedicado para PC=PC+4
  // Decode stage pipeline register and logic
  flopenrc #(96) regD(clk, reset, FlushD, ~StallD, 
                      {InstrF, PCF, PCPlus4F},
                      {InstrD, PCD, PCPlus4D});
  /*registrador regD:
  clk, reset: controle basico desse regsitrador
  FlushD: Clear
    Quando =1, a borda de subida do clock limpa as saidas
    Sem necessariamente resetar tudo, como o reset
    Reset: A qualquer momento pode zerar as saidas do registrador.
    Clear: Depende do coock para zerar as saidas.
  ~StallD: Enable 
    Na mesma logica de pcreg
  {InstrF, PCF, PCPlus4F}
    Saidas juntas em um "unico conjunto de sinais
  {InstrD, PCD, PCPlus4D}
    Saidas juntas em um "unico conjunto de sinais*/
  assign opD       = InstrD[6:0];
  assign funct3D   = InstrD[14:12];
  assign funct7b5D = InstrD[30];
  assign Rs1D      = InstrD[19:15];
  assign Rs2D      = InstrD[24:20];
  assign RdD       = InstrD[11:7];
	/*Todos os valores produzidos por Register File (instanciado em breve dentro de datapath).
  opD =InstrD[6:0]: opcode (identifica o tipo de instrucao)
  funct3D = InstrD[14:12]: function3 (complemento do opcode)
  funct7b5D =InstrD[30]; function7, bit5 (complemento "final" do opcode)
  Rs1D =InstrD[19:15]; Indice de rs1
  Rs2D =InstrD[24:20]; Indice de rs2
  RdD =InstrD[11:7]; Indice de rd*/
  regfile        rf(clk, RegWriteW, Rs1D, Rs2D, RdW, ResultW, RD1D, RD2D);
  //instanciação e controle dos registradores de Register FIle 
    //Para serem lidos e escritos de fomra sincrona.
  extend         ext(InstrD[31:7], ImmSrcD, ImmExtD);
  //Calculo e extensao (de 12bits a 32bits) do immediato.
  floprc #(175) regE(clk, reset, FlushE, 
                     {RD1D, RD2D, PCD, Rs1D, Rs2D, RdD, ImmExtD, PCPlus4D}, 
                     {RD1E, RD2E, PCE, Rs1E, Rs2E, RdE, ImmExtE, PCPlus4E});
	/*Registrador regE (primeiro a iniciar o carregamento de informaçoes pelo circuito
  clk, reset
  FlushE
  {RD1D, RD2D, PCD, Rs1D, Rs2D, RdD, ImmExtD, PCPlus4D}
  {RD1E, RD2E, PCE, Rs1E, Rs2E, RdE, ImmExtE, PCPlus4E}*/
  mux3   #(32)  faemux(RD1E, ResultW, ALUResultM, ForwardAE, SrcAE);
  //MUX de controle para entradaA da ULA.
  mux3   #(32)  fbemux(RD2E, ResultW, ALUResultM, ForwardBE, WriteDataE);
  //Primeiro MUX de controle para entradaB da ULA.
  mux2   #(32)  srcbmux(WriteDataE, ImmExtE, ALUSrcE, SrcBE);
  //segundo MUX de controle pra entradaB da ULA.
  alu           alu(SrcAE, SrcBE, ALUControlE, ALUResultE, ZeroE);
  //INstancia da ULA
    //Com suas entradas, sinal de controle, saidas e sinais para o modulo de controle (ZeroE).
  adder         branchadd(ImmExtE, PCE, PCTargetE);
  //somador dedicado a calcular PCTargetE.
  // Memory stage pipeline register
  flopr  #(101) regM(clk, reset, 
                     {ALUResultE, WriteDataE, RdE, PCPlus4E},
                     {ALUResultM, WriteDataM, RdM, PCPlus4M});
	/*registrador regM: Fica antes de Data Memory (passando informações de EX para MEM).
  clk, reset: Controlw basico
    Reset para lidar com possiveis problemas mais graves.
  {ALUResultE, WriteDataE, RdE, PCPlus4E}
    Entradas (de EX), prestes a entrar no proximo pulso de clock.
  {ALUResultM, WriteDataM, RdM, PCPlus4M}
    Saidas arualizadas, ja direcionando as informações para Data Memory*/
  // Writeback stage pipeline register and logic
  flopr  #(101) regW(clk, reset, 
                     {ALUResultM, ReadDataM, RdM, PCPlus4M},
                     {ALUResultW, ReadDataW, RdW, PCPlus4W});
  /*registrador regW: ANtes de write back (passando informações de Data Memory)
  clk, reset: cotrole basico desse regsitrador
  {ALUResultM, ReadDataM, RdM, PCPlus4M}: Entrada
  {ALUResultW, ReadDataW, RdW, PCPlus4W}: Saida*/
  //OBS: A medida que os dados vao sendo usados no circuito, é necesario passae cada vez menos informaçõea adiante
    //Por isso à medida que se "avança" no circuito, se usa cada vez menos regsitradores.
  //RegE é chamado com 175 bits pois a soma de bits que cada sinal armazenadp usa resulta em 175 bits ao total
  //RegM e RegW é chamado com 101 bits pois a soma de bits que cada sinal armazenadp usa resulta em 101 bits ao total
  mux3   #(32)  resultmux(ALUResultW, ReadDataW, PCPlus4W, ResultSrcW, ResultW);	
  //MUX para definir o que sera escrito no registrador em Register File.
endmodule


module regfile(input  logic        clk, 
               input  logic        we3, 
               input  logic [ 4:0] a1, a2, a3, 
               input  logic [31:0] wd3, 
               output logic [31:0] rd1, rd2);

  logic [31:0] rf[31:0];

  // three ported register file
  // read two ports combinationally (A1/RD1, A2/RD2)
  // write third port on rising edge of clock (A3/WD3/WE3)
  // write occurs on falling edge of clock
  // register 0 hardwired to 0

  always_ff @(negedge clk)
    if (we3) rf[a3] <= wd3;	

  assign rd1 = (a1 != 0) ? rf[a1] : 0;
  assign rd2 = (a2 != 0) ? rf[a2] : 0;
endmodule

module adder(input  [31:0] a, b,
             output [31:0] y);

  assign y = a + b;
endmodule

module extend(input  logic [31:7] instr,
              input  logic [1:0]  immsrc,
              output logic [31:0] immext);
 
  always_comb
    case(immsrc) 
               // I-type 
      2'b00:   immext = {{20{instr[31]}}, instr[31:20]};  
               // S-type (stores)
      2'b01:   immext = {{20{instr[31]}}, instr[31:25], instr[11:7]}; 
               // B-type (branches)
      2'b10:   immext = {{20{instr[31]}}, instr[7], instr[30:25], instr[11:8], 1'b0}; 
               // J-type (jal)
      2'b11:   immext = {{12{instr[31]}}, instr[19:12], instr[20], instr[30:21], 1'b0}; 
      default: immext = 32'bx; // undefined
    endcase             
endmodule
//por padrao todos os flipflops usam 8bits
module flopr #(parameter WIDTH = 8)
              (input  logic             clk, reset,
               input  logic [WIDTH-1:0] d, 
               output logic [WIDTH-1:0] q);

  always_ff @(posedge clk, posedge reset)
    if (reset) q <= 0;
    else       q <= d;
endmodule
/*flopr: flipflop apenas com reset*/
module flopenr #(parameter WIDTH = 8)
                (input  logic             clk, reset, en,
                 input  logic [WIDTH-1:0] d, 
                 output logic [WIDTH-1:0] q);

  always_ff @(posedge clk, posedge reset)
    if (reset)   q <= 0;
    else if (en) q <= d;
endmodule
/*flopenr: flip flop com enable e reset*/
module flopenrc #(parameter WIDTH = 8)
                (input  logic             clk, reset, clear, en,
                 input  logic [WIDTH-1:0] d, 
                 output logic [WIDTH-1:0] q);

  always_ff @(posedge clk, posedge reset)
    if (reset)   q <= 0;
    else if (en) 
      if (clear) q <= 0;
      else       q <= d;
endmodule
/*flopenrc: flip flop com enable, reset e clear*/
module floprc #(parameter WIDTH = 8)
              (input  logic clk,
               input  logic reset,
               input  logic clear,
               input  logic [WIDTH-1:0] d, 
               output logic [WIDTH-1:0] q);

  always_ff @(posedge clk, posedge reset)
    if (reset) q <= 0;
    else       
      if (clear) q <= 0;
      else       q <= d;
endmodule
/*floprc: flipflop com reset e clear*/
module mux2 #(parameter WIDTH = 8)
             (input  logic [WIDTH-1:0] d0, d1, 
              input  logic             s, 
              output logic [WIDTH-1:0] y);

  assign y = s ? d1 : d0; 
endmodule

module mux3 #(parameter WIDTH = 8)
             (input  logic [WIDTH-1:0] d0, d1, d2,
              input  logic [1:0]       s, 
              output logic [WIDTH-1:0] y);

  assign y = s[1] ? d2 : (s[0] ? d1 : d0); 
endmodule

module imem(input  logic [31:0] a,
            output logic [31:0] rd);

  logic [31:0] RAM[63:0];

  initial
      $readmemh("riscvtest.txt",RAM);

  assign rd = RAM[a[31:2]]; // word aligned
endmodule

module dmem(input  logic        clk, we,
            input  logic [31:0] a, wd,
            output logic [31:0] rd);

  logic [31:0] RAM[63:0];

  assign rd = RAM[a[31:2]]; // word aligned

  always_ff @(posedge clk)
    if (we) RAM[a[31:2]] <= wd;
endmodule

module alu(input  logic [31:0] a, b,
           input  logic [2:0]  alucontrol,
           output logic [31:0] result,
           output logic        zero);

  logic [31:0] condinvb, sum;
  logic        v;              // overflow
  logic        isAddSub;       // true when is add or subtract operation

  assign condinvb = alucontrol[0] ? ~b : b;
  assign sum = a + condinvb + alucontrol[0];
  assign isAddSub = ~alucontrol[2] & ~alucontrol[1] |
                    ~alucontrol[1] &  alucontrol[0];

  always_comb
    case (alucontrol)
      3'b000:  result = sum;         // add
      3'b001:  result = sum;         // subtract
      3'b010:  result = a & b;       // and
      3'b011:  result = a | b;       // or
      3'b100:  result = a ^ b;       // xor
      3'b101:  result = sum[31] ^ v; // slt
      3'b110:  result = a << b[4:0]; // sll
      3'b111:  result = a >> b[4:0]; // srl
      default: result = 32'bx;
    endcase

  assign zero = (result == 32'b0);
  assign v = ~(alucontrol[0] ^ a[31] ^ b[31]) & (a[31] ^ sum[31]) & isAddSub;
  
endmodule