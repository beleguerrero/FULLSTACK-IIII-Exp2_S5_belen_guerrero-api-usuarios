package cl.duoc.mi_foro_usuarios.dto;

import jakarta.validation.constraints.Min;
import lombok.AllArgsConstructor;
import lombok.Builder;
import lombok.Data;
import lombok.NoArgsConstructor;

@Data 
@NoArgsConstructor 
@AllArgsConstructor 
@Builder 
public class UsuarioRequestOptionalDTO {

    private String usuario;
    private String password;
    private String nombre;
    private String correo;
    private Long tipoUsuarioId;
    private Boolean activo;

}
